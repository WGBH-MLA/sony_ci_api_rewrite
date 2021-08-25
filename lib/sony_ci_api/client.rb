require 'json'
require 'uri'
require 'faraday'
require 'faraday_middleware'
require 'active_support/core_ext/string/inflections'
require 'forwardable'
require 'base64'
require 'yaml'

module SonyCiApi
  class Client
    BASE_URL = "https://api.cimediacloud.com".freeze
    BASE_UPLOAD_URL = "https://io.cimediacloud.com".freeze

    attr_reader :config,   # stores the config for the connection, including credentials.
                :response  # stores the most recent response; default nil

    # Often we are only working in a single workspace, so allow for a default
    # to be set here.
    attr_accessor :workspace_id

    def initialize( config = {} )
      load_config! config
      # Set the default workspace, if present, from the config
      @workspace_id = self.config.delete(:workspace_id)
    end

    def load_config!(config={})
      if File.exist?(config.to_s)
        template = ERB.new(File.read(config))
        @config = YAML.load(template.result(binding), symbolize_names: true)
      elsif config.is_a? Hash
        @config = config
      else
        raise InvalidConfigError, "config is expected to be a valid YAML file or " \
                             "a Hash, but #{config.class} was given. "
      end
    rescue Psych::SyntaxError => e
      raise InvalidConfigError, e.message
    end


    def conn
      @conn ||= api_conn
    end

    def api_conn
      @api_conn ||= Faraday.new(url: BASE_URL) do |f|
        f.request :json
        f.response :json
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end

    def upload_conn
      @upload_conn ||= Faraday.new(url: BASE_UPLOAD_URL) do |f|
        f.request :multipart
        f.request :url_encoded
        f.response :json
        f.response :raise_error
        f.adapter Faraday.default_adapter
      end
    end

    def get(path, params: {}, headers: {})
      send_request(:get, path, params: params, headers: headers)
    end

    def post(path, params: {}, headers: {})
      send_request(:post, path, params: params, headers: headers)
    end

    def put(path, params: {}, headers: {})
      send_request(:put, path, params: params, headers: headers)
    end

    def delete(path, params: {}); end        # TODO

    def access_token
      @access_token ||= begin
        api_conn.basic_auth config[:username], config[:password]
        @response = api_conn.post(
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

    def workspaces(**params)
      get('/workspaces', params: params)['items']
    end

    def workspace_search( workspace_id = self.workspace_id, **params )
      get("/workspaces/#{workspace_id}/search", params: params)['items']
    end

    def webhooks( workspace_id = self.workspace_id, **params)
      get("/networks/#{workspace['network']['id']}/webhooks", params: params)['items']
    end

    def workspace_id=(wid)
      # unset all the cached attrs that depend on workspace_id
      @workspace = nil
      @workspace_id = wid
    end

    def workspace
      raise 'You must first set workspace_id' unless workspace_id
      @workspace ||= workspaces.detect { |ws| ws['id'] == workspace_id }
    end

    def upload(filepath, content_type:)
      with_upload_conn do
        params = {
          filename: Faraday::FilePart.new( filepath, content_type, nil,
                                           'Content-Disposition' => 'form-data')
        }
        post('/upload', params: params)
      end
    end

    def with_upload_conn
      raise 'block required' unless block_given?
      @conn = upload_conn
      yield
    ensure
      @conn = api_conn
    end

    def asset(asset_id)
      get "/assets/#{asset_id}"
    end

    def asset_download(asset_id)
      get "/assets/#{asset_id}/download"
    end

    def workspace_contents( workspace_id = self.workspace_id, **params )
      get("/workspaces/#{workspace_id}/contents", params: params)['items']
    end


    private

      def send_request(http_method, path, params: {}, headers: {})
        @response = nil # reset the last response explicitly in case of error.
        conn.authorization :Bearer, access_token
        @response = conn.send(http_method, path, camelize_params(params), headers )
        @response.body
      rescue => error
        raise Error.create_from(error)
      end


    # Class methods
    class << self
      # Converts a params hash (with symbol keys that have underscores) to
      # a param hash where the keys are strings, and lower-camelcase, like the
      # Sony Ci API expects.
      def camelize_params(params={})
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
