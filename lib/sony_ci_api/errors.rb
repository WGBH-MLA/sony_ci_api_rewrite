module SonyCiApi
  class Error < StandardError
    # Creates a new Error instance, with optional :from_error as the original
    # error that was raised. The purpose of SonyCiApi::Error and subclasses is
    # to wrap ALL raised errors, such that any error coming out of the gem can
    # be caught by rescuing from the base class SonyCiApi::Error.
    def initialize(msg = nil, from_error: nil)
      @from_error = from_error
      super(msg)
    end

    # Returns the error message. Note that this method is called by #message,
    # and not the other way around, so overwriting #message just doesn't work.
    # Use the @from_error#message if present, otherwise default to super.
    def to_s
      from_error(:message) || super
    end

    # Returns @from_error if no args are passed.
    # When args are passed, uses the first arg as a method name and calls that
    # method on @from_error with the remaining args.
    # This is a convenience method to avoid having to check for the existence
    # of @from_error (which can be nil) everytime we want to use it.
    def from_error(*args)
      return nil if @from_error.nil?
      return @from_error if args.empty?
      method = args.shift
      @from_error.send(method, *args)
    end

    # Returns a hash of Error info that is ready to be serialized into JSON for
    # HTTP responses, e.g. from a Rails controller.
    def to_h
      {
        "error" => self.class.to_s,
        "error_message" => message,
        "from_error" => from_error ? from_error.class.to_s : nil
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

  # Since we use Faraday currently, this module provides methods that know how
  # to get data out of Faraday::Error instances specifically. Intended to be
  # mixed into SonyCiApi::HttpError for as long as we use Faraday, but can be
  # easily replaced if we end up using a different HTTP client down the road.
  module FromFaradayError
    def http_status
      response[:status] if response
    end

    def request_url
      request[:url_path] if request
    end

    def request_params
      request[:params] if request
    end

    def to_h
      super.merge(
        {
          "https_status" => http_status,
          "request_url" => request_url,
          "request_params" => request_params
        }.compact
      )
    end

    private

      # Returns the @from_error if it's a Faraday::Error; else returns nil
      def faraday_error
        @faraday_error ||= from_error if from_error.is_a? Faraday::Error
      end

      def request
        faraday_error.request if faraday_error.respond_to?(:request)
      end

      def response
        faraday_error.response if faraday_error.respond_to?(:response)
      end
  end

  # HttpError base class for wrapping HTTP errors returned from Sony Ci API.
  # Since we use Faraday for now, include the module that knows how to get data
  # out of Faraday::Error instances.
  class HttpError < Error
    include FromFaradayError
  end

  # Client errors
  class ClientError < HttpError; end
  class BadRequestError < ClientError; end
  class UnauthorizedError < ClientError; end
  class ForbiddenError < ClientError; end
  class NotFoundError < ClientError; end
  class ProxyAuthError < ClientError; end
  class ConflictError < ClientError; end
  class UnprocessableEntityError < ClientError; end
  # Server errors
  class ServerError < HttpError; end
  class TimeoutError < ServerError; end
  class NilStatusError < ServerError; end
  class ConnectionFailed < ServerError; end
  class SSLError < ServerError; end

  # Other errors not associated with HTTP.
  class InvalidConfigError < Error; end
end
