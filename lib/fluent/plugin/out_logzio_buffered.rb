module Fluent
  class LogzioOutputBuffered < Fluent::BufferedOutput
    Fluent::Plugin.register_output('logzio_buffered', self)
    config_param :endpoint_url, :string, default: nil
    config_param :output_include_time, :bool, default: true
    config_param :output_include_tags, :bool, default: true
    config_param :retry_count, :integer, default: 3 # How many times to resend failed bulks. Undocumented because not suppose to be changed
    config_param :http_idle_timeout, :integer, default: 5
    config_param :output_tags_fieldname, :string, default: 'fluentd_tags'

    unless method_defined?(:log)
      define_method('log') { $log }
    end

    def configure(conf)
      super
      $log.debug "Logzio url #{@endpoint_url}"
    end

    def start
      super
      require 'net/http/persistent'
      @uri = URI @endpoint_url
      @http = Net::HTTP::Persistent.new 'fluent-plugin-logzio', :ENV
      @http.headers['Content-Type'] = 'text/plain'
      @http.idle_timeout = @http_idle_timeout
      @http.socket_options << [Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1]
      log.debug "Started logzio shipper.."
    end

    def shutdown
      super
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      records = []

      chunk.msgpack_each {|tag,time,record|
        begin
          record['@timestamp'] ||= Time.at(time).iso8601(3) if @output_include_time
          record[@output_tags_fieldname] ||= tag.to_s if @output_include_tags
          records.push(Yajl.dump(record))
        rescue
          log.error("Adding record #{record} to buffer failed. Exception: #{$!}")
        end
      }

      log.debug "Got flush timeout, containing #{records.length} chunks"

      # Setting our request
      post = Net::HTTP::Post.new @uri.request_uri

      # Logz.io bulk http endpoint expecting log line with \n delimiter
      post.body = records.join("\n")

      begin
        response = @http.request @uri, post
        should_retry = true

        if response.code != '200'
          if response.code == '401'
            log.error("You are not authorized with Logz.io! Token OK? dropping logs...")
            should_retry = false
          end

          if response.code == '400'
            log.info("Got 400 code from Logz.io. This means that some of your logs are too big, or badly formatted. Response: #{response.body}")
            should_retry = false
          end

          # If any other non-200 or 400/401, we will try to resend it after 2, 4 and 8 seconds. Then we will give up
          sleep_interval = 2

          if should_retry
            log.debug "Got HTTP #{response.code} from logz.io, not giving up just yet"
            @retry_count.times do |counter|
              log.debug "Sleeping for #{sleep_interval} seconds, and trying again."
              sleep(sleep_interval)

              # Retry
              response = @http.request @uri, post

              # Sucecss, no further action is needed
              if response.code == 200
                log.debug "Successfuly sent the failed bulk."
                break
              else
                # Doubling the sleep interval
                sleep_interval *= 2

                if counter == @retry_count - 1
                  log.error "Could not send your bulk after 3 tries. Sorry. Got HTTP #{response.code} with body: #{response.body}"
                end
              end
            end
          end
        end
      rescue StandardError => error
        log.error "Error connecting to logzio. Got exception: #{error}"
      end
    end
  end
end
