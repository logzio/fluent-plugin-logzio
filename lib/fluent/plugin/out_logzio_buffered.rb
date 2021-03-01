require 'time'
require 'fluent/plugin/output'
require 'zlib'
require 'stringio'

module Fluent::Plugin
  class LogzioOutputBuffered < Output
    Fluent::Plugin.register_output('logzio_buffered', self)

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
      log.debug "Sending a bulk of #{bulk_records.size} records, size #{bulk_size}B to Logz.io"

      # Setting our request
      post = Net::HTTP::Post.new @uri.request_uri

      # Logz.io bulk http endpoint expecting log line with \n delimiter
      post.body = bulk_records.join("\n")
      if gzip
        post.body = compress(post.body)
      end
      sleep_interval = @retry_sleep

      begin
        @retry_count.times do |counter|
          should_retry = true
          begin
            response = @http.request @uri, post
            if response.code != '200'
              if response.code == '401'
                log.error "You are not authorized with Logz.io! Token OK? dropping logs..."
                should_retry = false
              elsif response.code == '400'
                log.info "Got 400 code from Logz.io. This means that some of your logs are too big, or badly formatted. Response: #{response.body}"
                should_retry = false
              else
                log.warn "Got HTTP #{response.code} from Logz.io, not giving up just yet (Try #{counter + 1}/#{@retry_count})"
              end
            else
              log.debug "Successfully sent bulk of #{bulk_records.size} records, size #{bulk_size}B to Logz.io"
              should_retry = false
            end
          rescue StandardError => e
            log.warn "Error connecting to Logz.io. Got exception: #{e} (Try #{counter + 1}/#{@retry_count})"
          end

          if should_retry
            if counter == @retry_count - 1
              log.error "Could not send your bulk after #{retry_count} tries Sorry! Your bulk is: #{post.body}"
              break
            end
            sleep(sleep_interval)
            sleep_interval *= 2
          else
            return
          end
        end
      rescue Exception => e
        log.error "Got unexpected exception! Here: #{e}"
      end
    end

    def compress(string)
      wio = StringIO.new("w")
      w_gz = Zlib::GzipWriter.new(wio)
      w_gz.write(string)
      w_gz.close
      wio.string
    end
  end
end
