module LocaleApp
  class ApiCaller
    include ::LocaleApp::Routes

    DEFAULT_RETRY_LIMIT = 1

    # we can retry more in the gem than we can
    # when running in process
    attr_accessor :max_connection_attempts

    attr_reader :endpoint, :options, :connection_attempts

    def initialize(endpoint, options = {})
      @endpoint, @options = endpoint, options
      @connection_attempts = 0
      @max_connection_attempts = options[:max_connection_attempts] || DEFAULT_RETRY_LIMIT
    end

    def call(obj)
      method, url = send("#{endpoint}_endpoint")
      LocaleApp.debug("API CALL: #{method} #{url}")
      success = false
      while connection_attempts < max_connection_attempts
        sleep_if_retrying
        response = make_call(method, url)
        LocaleApp.debug("RESPONSE: #{response.code}")
        valid_response_codes = (200..207).to_a
        if valid_response_codes.include?(response.code.to_i)
          if options[:success]
            LocaleApp.debug("CALLING SUCCESS HANDLER: #{options[:success]}")
            obj.send(options[:success], response)
          end
          success = true
          break
        end
      end

      if !success && options[:failure]
        obj.send(options[:failure], response)
      end
    end

    private
    def make_call(method, url)
      begin
        @connection_attempts += 1
        LocaleApp.debug("ATTEMPT #{@connection_attempts}")
        if method == :post
          RestClient.send(method, url, options[:payload])
        else
          RestClient.send(method, url)
        end
      rescue RestClient::ResourceNotFound,
        RestClient::InternalServerError,
        RestClient::BadGateway,
        RestClient::ServiceUnavailable,
        RestClient::GatewayTimeout => error
        return error.response
      end
    end

    def sleep_if_retrying
      if @connection_attempts > 0
        time = @connection_attempts * 5
        LocaleApp.debug("Sleeping for #{time} before retrying")
        sleep time
      end
    end
  end
end
