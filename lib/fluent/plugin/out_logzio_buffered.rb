require 'time'
require 'fluent/plugin/output'
require 'zlib'
require 'stringio'

module Fluent::Plugin
  class LogzioOutputBuffered < Output
    Fluent::Plugin.register_output('logzio_buffered', self)
    class RetryableResponse < StandardError; end

    helpers :compat_parameters

    config_param :endpoint_url, :string, default: nil
    config_param :output_include_time, :bool, default: true
    config_param :output_include_tags, :bool, default: true
    config_param :retry_count, :integer, default: 4 # How many times to resend failed bulks. Undocumented because not suppose to be changed
    config_param :retry_sleep, :integer, default: 2 # How long to sleep initially between retries, exponential step-off
    config_param :bulk_limit, :integer, default: 1000000 # Make sure submission to LogzIO does not exceed 1MB limit and leave some overhead
    config_param :bulk_limit_warning_limit, :integer, default: nil # If fluent warnings are sent to the Logzio output, truncating is necessary to prevent a recursion
    config_param :http_idle_timeout, :integer, default: 5
    config_param :output_tags_fieldname, :string, default: 'fluentd_tags'
    config_param :proxy_uri, :string, default: nil
    config_param :proxy_cert, :string, default: nil
    config_param :gzip, :bool, default: false # False for backward compatibility

    def configure(conf)
      super
      compat_parameters_convert(conf, :buffer)

      log.debug "Logz.io URL #{@endpoint_url}"

      if conf['proxy_uri']
        log.debug "Proxy #{@proxy_uri}"
        ENV['http_proxy'] = @proxy_uri
      end

      if conf['proxy_cert']
        log.debug "Proxy #{@proxy_cert}"
        ENV['SSL_CERT_FILE'] = @proxy_cert
      end
      @metric_labels = {
        type: 'logzio_buffered',
        plugin_id: 'out_logzio',
      }
      @metrics = {
        status_codes: get_gauge(
          :logzio_status_codes,
          'Status codes received from Logz.io', {"status_code":""}),
      }

    end

    def initialize
      super
      @registry = ::Prometheus::Client.registry
    end

    def start
      super
      require 'net/http/persistent'
      @uri = URI @endpoint_url
      @http = Net::HTTP::Persistent.new name: 'fluent-plugin-logzio', proxy: :ENV
      @http.headers['Content-Type'] = 'text/plain'
      if @gzip
        @http.headers['Content-Encoding'] = 'gzip'
      end
      @http.idle_timeout = @http_idle_timeout
      @http.socket_options << [Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1]

      log.debug "Started Logz.io shipper.."
    end

    def shutdown
      super
    end

    def formatted_to_msgpack_binary?
      true
    end

    def multi_workers_ready?
      true
    end

    def format(tag, time, record)
      if time.is_a?(Fluent::EventTime)
        sec_frac = time.to_f
      else
        sec_frac = time * 1.0
      end
      [tag, sec_frac, record].to_msgpack
    end

    def write(chunk)
      encode_chunk(chunk) { |bulk_records, bulk_size|
        send_bulk(bulk_records, bulk_size)
      }
    end

    def encode_chunk(chunk)
      records = []
      bulk_size = 0
      chunk.each { |tag, time, record|
        record['@timestamp'] ||= Time.at(time).iso8601(3) if @output_include_time
        record[@output_tags_fieldname] ||= tag.to_s if @output_include_tags

        begin
          json_record = Yajl.dump(record)
          record_size = json_record.size + (1 if !records.empty?).to_i # Accounting for trailing "\n"
        rescue
          log.error "Adding record #{record} to buffer failed. Exception: #{$!}"
          next
        end

        if record_size > @bulk_limit
          if @bulk_limit_warning_limit.is_a?(Integer)
            log.warn "Record with size #{record_size} exceeds #{@bulk_limit} and can't be sent to Logz.io. Record starts with (truncated at #{@bulk_limit_warning_limit} characters): #{json_record[0,@bulk_limit_warning_limit]}"
            # Send the full message to debug facility
            log.debug "Record with size #{record_size} exceeds #{@bulk_limit} and can't be sent to Logz.io. Record is: #{json_record}"
          else
            log.warn "Record with size #{record_size} exceeds #{@bulk_limit} and can't be sent to Logz.io. Record is: #{json_record}"
          end
          next
        end
        if bulk_size + record_size > @bulk_limit
          yield(records, bulk_size)
          records = []
          bulk_size = 0
        end
        records.push(json_record)
        bulk_size += record_size
      }
      if records
        yield(records, bulk_size)
      end
    end

    def send_bulk(bulk_records, bulk_size)
      response = do_post(bulk_records, bulk_size)
      
      @metrics[:status_codes].increment(labels: merge_labels({'status_code': response.code.to_s}))

      if not response.code.start_with?('2')
        if response.code == '400'
          log.warn "Received #{response.code} from Logzio. Some logs may be malformed or too long. Valid logs were succesfully sent into the system. Will try to proccess and send bad logs. Response body: #{response.body}"
          process_code_400(bulk_records, Yajl.load(response.body))
        elsif response.code == '401'
          log.error "Received #{response.code} from Logzio. Unauthorized, please check your logs shipping token. Will not retry sending. Response body: #{response.body}"
        else
          log.debug "Failed request body: #{post.body}"
          log.error "Error while sending POST to #{@uri}: #{response.body}"
          raise RetryableResponse, "Logzio listener returned (#{response.code}) for #{@uri}:  #{response.body}", []
        end
      end
    end

    def do_post(bulk_records, bulk_size)
      log.debug "Sending a bulk of #{bulk_records.size} records, size #{bulk_size}B to Logz.io"

      # Setting our request
      post = Net::HTTP::Post.new @uri.request_uri

      # Logz.io bulk http endpoint expecting log line with \n delimiter
      post.body = bulk_records.join("\n")
      if gzip
        post.body = compress(post.body)
      end

      begin
        response = @http.request @uri, post
        rescue Net::HTTP::Persistent::Error => e
          raise e.cause
        return response
      end
    end

    def process_code_400(bulk_records, response_body)
      max_log_field_size_bytes = 32000
      malformed_logs_counter = response_body['malformedLines'].to_i
      oversized_logs_counter = response_body['oversizedLines'].to_i
      new_bulk = []
      for log_record in bulk_records
        log.debug "Malformed lines: #{malformed_logs_counter}"
        log.debug "Oversized lines: #{oversized_logs_counter}"
        if malformed_logs_counter == 0 && oversized_logs_counter == 0
          log.debug "No malformed lines, breaking"
          break
        end
        log_size = log_record.size
        # Handle oversized log:
        if log_size >= max_log_field_size_bytes
          new_log = Yajl.load(log_record)
          new_log['message'] = new_log['message'][0,  max_log_field_size_bytes - 1]
          log.info "new log: #{new_log}" # TODO
          new_bulk.append(Yajl.dump(new_log))
          oversized_logs_counter -= 1
        end
      end
      if new_bulk.size > 0
        log.debug "Number of fixed bad logs to send: #{new_bulk.size}"
        response = do_post(new_bulk, new_bulk.size)
        if response.code.start_with?('2')
          log.info "Succesfully sent bad logs"
        else
          log.warn "While trying to send fixed bad logs, got #{response.code} from Logz.io, will not try to re-send"
        end
      end
    end

    def compress(string)
      wio = StringIO.new("w")
      w_gz = Zlib::GzipWriter.new(wio)
      w_gz.write(string)
      w_gz.close
      wio.string
    end

    def merge_labels(extra_labels= {})
      @metric_labels.merge extra_labels
    end

    def get_gauge(name, docstring, extra_labels = {})
      if @registry.exist?(name)
        @registry.get(name)
      else
        @registry.gauge(name, docstring: docstring, labels: @metric_labels.keys + extra_labels.keys)
      end
    end
  end
end
