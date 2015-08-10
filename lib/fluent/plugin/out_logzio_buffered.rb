module Fluent
  class LogzioOutputBuffered < Fluent::BufferedOutput
    Fluent::Plugin.register_output('logzio_buffered', self)
    config_param :endpoint_url, :string, default: nil
    config_param :output_include_time, :bool, default: true  # Recommended

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
      @http.headers['Content-Type'] = 'text'
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
        record['timestamp'] ||= Time.at(time).iso8601 if @output_include_time
        records.push(record.to_json)
      }
      $log.debug "#{records.length} records sent"
      post = Net::HTTP::Post.new @uri.request_uri
      post.body = records.join('\n')
      begin
        response = @http.request @uri, post
        $log.debug "HTTP Response code #{response.code}"
        $log.error response.body if response.code != '200'
      rescue StandardError
        $log.error "Error connecting to logzio verify the url #{@loggly_url}"
      end
    end
  end
end
