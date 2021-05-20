require 'json'
require 'uri'
require 'faraday'
require 'faraday_middleware'
require 'active_support/core_ext/string/inflections'
require 'forwardable'
require 'base64'

module SonyCiApi
  class Client
    BASE_URL = "https://api.cimediacloud.com".freeze

    attr_reader :config,   # stores the config for the connection, including credentials.
                :response  # stores the most recent response; default nil

    def initialize(config={})
      @config = File.exist?(config.to_s) ? YAML.safe_load(File.read(config), symbolize_names: true) : config
    end

    def conn
      @conn ||= Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json
        f.response :raise_error
      end
    end

    def get(path, params: {}, headers: {})
      send_request(:get, path, params: params, headers: headers)
    end

    def post(path, params: {}, headers: {})
      send_request(:post, path, params: params, headers: headers)
    end

    def put(path, params: {}); end           # TODO
    def delete(path, params: {}); end        # TODO

    def access_token
      @access_token ||= begin
        conn.basic_auth config[:username], config[:password]
        @response = conn.post(
          '/oauth2/token',
          {
            grant_type: 'password',
            client_id: config[:client_id],
            client_secret: config[:client_secret]
          }
        )
        @response.body['access_token']
      end
    end

    def workspace_search(workspace_id, **params)
      get("/workspaces/#{workspace_id}/search", params: params)['items']
    end


    private

      def send_request(http_method, path, params: {}, headers: {})
        @response = nil # reset the last response explicitly in case of error.
        conn.authorization :Bearer, access_token
        @response = conn.send(http_method, url(path), camelize_params(params), headers )
        @response.body
      rescue Faraday::ResourceNotFound, Faraday::BadRequestError => e
        # For 4xx and 5xx responses that come with a Sony Ci error code and
        # message, put those into the error and re-raise it.
        response_body = JSON.parse(e.response[:body])
        raise e, "#{response_body['code']} - #{response_body['message']}"
      end


    # Class methods
    class << self
      def url(path, **params)
        url_params = URI.encode_www_form(camelize_params(params))
        full_url = File.join( [ BASE_URL, path.to_s ].reject(&:empty?) )
        full_url = [ full_url, url_params ].reject(&:empty?).join('?')
      end

      # Converts a params hash (with symbol keys that have underscores) to
      # a param hash where the keys are strings, and lower-camelcase, like the
      # Sony Ci API expects.
      def camelize_params(**params)
        params.transform_keys { |key| key.to_s.camelize(:lower) }
      end
    end

    # Delegate some instance methods to class methods so we can call them
    # directly in an instance without having to call `self.class`.
    extend Forwardable
    def_delegator self, :url
    def_delegator self, :camelize_params
  end
end
