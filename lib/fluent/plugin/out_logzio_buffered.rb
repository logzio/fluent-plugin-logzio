module Fluent
  class LogzioOutputBuffered < Fluent::BufferedOutput
    Fluent::Plugin.register_output('logzio_buffered', self)
    config_param :endpoint_url, :string, default: nil
    config_param :output_include_time, :bool, default: true
    config_param :output_include_tags, :bool, default: true
    config_param :retry_count, :integer, default: 3 # How many times to resend failed bulks. Undocumented because not suppose to be changed

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
      $log.debug "Started logzio shipper.."
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
        record['@timestamp'] ||= Time.at(time).iso8601 if @output_include_time
        record['fluentd_tags'] ||= tag.to_s if @output_include_tags
        records.push(record.to_json)
      }

      $log.debug "Got flush timeout, containing #{records.length} chunks"

      # Setting our request
      post = Net::HTTP::Post.new @uri.request_uri      

      # Logz.io bulk http endpoint expecting log line with \n delimiter
      post.body = records.join("\n")

      begin
        response = @http.request @uri, post
        $log.debug "HTTP Response code #{response.code}"

        if response.code != '200'

          $log.debug "Got HTTP #{response.code} from logz.io, not giving up just yet"

          # If any other non-200, we will try to resend it after 2, 4 and 8 seconds. Then we will give up
            
          sleep_interval = 2
          @retry_count.times do |counter|

            $log.debug "Sleeping for #{sleep_interval} seconds, and trying again."

            sleep(sleep_interval)

            # Retry
            response = @http.request @uri, post

            # Sucecss, no further action is needed
            if response.code == 200

              $log.debug "Successfuly sent the failed bulk."

              # Breaking out
              break

            else
              
              # Doubling the sleep interval
              sleep_interval *= 2

              if counter == @retry_count - 1

                $log.error "Could not send your bulk after 3 tries. Sorry. Got HTTP #{response.code}"
              end
            end
          end
        end
      rescue StandardError
        $log.error "Error connecting to logzio. verify the url #{@endpoint_url}"
      end
    end
  end
end
