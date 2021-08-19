module SonyCiApi
  class Error < StandardError
    def initialize(msg = nil, from_error: nil)
      @from_error = from_error
      super(msg)
    end

    def to_s
      from_error(:message) || super
    end

    def from_error(*args)
      return nil if @from_error.nil?
      return @from_error if args.empty?
      method = args.shift
      @from_error.send(method, *args)
    end

    def to_h
      {
        error: self.class,
        error_message: from_error(:message),
        from_error: from_error ? from_error.class : nil
      }
    end

    class << self
      # Factory class method that maps errors to subclasses of SonyCiApi::Error.
      # If the error is not explicitly mapped in error_class_map, returns an
      # instance of the SonyCiApi::Error.
      def create_from(error)
        error_class_map.fetch(error.class) do |klass|
          self
        end.new(from_error: error)
      end

      private
        def error_class_map
          @error_class_map ||= {
            Faraday::ClientError               => ClientError,
            Faraday::BadRequestError           => BadRequestError,
            Faraday::UnauthorizedError         => UnauthorizedError,
            Faraday::ForbiddenError            => ForbiddenError,
            Faraday::ResourceNotFound          => NotFoundError,
            Faraday::ProxyAuthError            => ProxyAuthError,
            Faraday::ConflictError             => ConflictError,
            Faraday::UnprocessableEntityError  => UnprocessableEntityError,
            Faraday::ServerError               => ServerError,
            Faraday::TimeoutError              => TimeoutError,
            Faraday::NilStatusError            => NilStatusError,
            Faraday::ConnectionFailed          => ConnectionFailed,
            Faraday::SSLError                  => SSLError
          }
        end
    end
  end

  # Module that knows how to extract info from Faraday errors.
  module FromFaradayError
    def to_json
      super.merge(
        {
          https_status: http_status,
          request_url: request_url,
          request_params: request_params
        }
      )
    end
  end

  # Base class for HTTP errors.
  class HttpError < Error;
    include FromFaradayError
  end
  class ClientError < HttpError; end
  class BadRequestError < ClientError; end
  class UnauthorizedError < ClientError; end
  class ForbiddenError < ClientError; end
  class NotFoundError < ClientError; end
  class ProxyAuthError < ClientError; end
  class ConflictError < ClientError; end
  class UnprocessableEntityError < ClientError; end
  class ServerError < HttpError; end
  class TimeoutError < ServerError; end
  class NilStatusError < ServerError; end
  class ConnectionFailed < Error; end
  class SSLError < Error; end

  # Other errors not associated with HTTP.
  class InvalidConfigError < Error; end
end
