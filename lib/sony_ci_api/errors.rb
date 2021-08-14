module SonyCiApi
  class Error < StandardError
    attr_reader :http_status, :error_code, :from_error

    def initialize(msg = nil, http_status: 500, from_error: nil, error_code: nil)
      @http_status = http_status
      @from_error = from_error
      @error_code = error_code
      full_msg = if error_code
        "#{error_code} - #{msg}"
      else
        msg
      end
      super(full_msg)
    end

    class << self
      # Maps non-SonyCiApi errors to subclasses of SonyCiApi::Error.
      def create_from(error)
        if error.is_a?(Faraday::Error)
          create_from_faraday_error(error)
        else
          # Default case, no special handling
          self.new(error.message, from_error: error)
        end
      end

      private
        def create_from_faraday_error(error)
          response_body = JSON.parse(error.response[:body])
          # Get the error class that corresponds with the HTTP response status,
          # defaulting to the base class SonyCiApi::Error if for some reason
          # the response status is not yet represented.
          error_class = {
            401 => UnauthorizedError,
            404 => NotFoundError
          }.fetch(error.response[:status], self)

          # Sony Ci puts the error message and error code in different places
          # for different errors.
          msg = response_body['message'] || response_body['error_description']
          error_code = response_body['code'] || response_body['error']

          error_class.new(msg, http_status: error.response[:status], from_error: error, error_code: error_code)
        end
    end
  end

  class InvalidConfigError < Error; end
  class UnauthorizedError < Error; end
  class NotFoundError < Error; end
end
