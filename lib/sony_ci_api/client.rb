# frozen_string_literal: true

require 'json'
require 'uri'
require 'faraday'
require 'faraday_middleware'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/hash/indifferent_access'
require 'forwardable'
require 'base64'
require 'yaml'
require 'erb'

module SonyCiApi
  class Client
    BASE_URL = "https://api.cimediacloud.com"
    BASE_UPLOAD_URL = "https://io.cimediacloud.com"
    
    # Some API endpoints require recursion, like fetching nested folder contents.
    # MAX_RECURSION sets the max recursion depth to avoid accidental API abuse.
    MAX_RECURSION = 5

    # API endpoints that returns a list from the 'items' property tend to also have pagination params 'limit' and 'offset'.
    MAX_ITEMS_PER_PAGE = 100
    MAX_PAGES = 1000
    MAX_ITEMS = MAX_ITEMS_PER_PAGE * MAX_PAGES

    attr_reader :config,   # stores the config for the connection, including credentials.
                :response  # stores the most recent response; default nil

    # Often we are only working in a single workspace, so allow for a default
    # to be set here.
    attr_accessor :workspace_id

    def initialize(config = {})
      load_config! config
      # Set the default workspace, if present, from the config
      @workspace_id = self.config.delete(:workspace_id)
    end

    def load_config!(config = {})
      if File.exist?(config.to_s)
        template = ERB.new(File.read(config))
        config_hash = YAML.safe_load(template.result(binding))
      elsif config.is_a? Hash
        config_hash = config
      else
        msg = if config.is_a? String
          "config file '#{config}' does not exist."
        else
          "config is expected to be a valid YAML file or a Hash, but #{config.class} was given. "
        end
        raise InvalidConfigError, msg
      end
      @config = config_hash.with_indifferent_access
    rescue Psych::SyntaxError, Psych::DisallowedClass => e
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

    def delete(path, params: {}, headers: {})
      send_request(:delete, path, params: params, headers: headers)
    end

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


    # Returns the 'items' property of the response fetching multiple pages as necessary.
    def get_items(path, params: {}, headers: {}, post: false)
      all_items = []
      paginate_params(params).map do |paginated_params|
        method = post ? :post : :get
        results = send(method, path, params: paginated_params, headers: headers).fetch('items', [])
        all_items += results
        # If the results are fewer than the page count that means we asked for more pages than
        # we actually have, so break early to avoid extraneous API requests.
        break if results.count < paginated_params[:limit]
      end
      all_items
    end


    def paginate_params(params={})
      params = params.with_indifferent_access
      limit = params.delete(:limit) || MAX_ITEMS_PER_PAGE
      offset = params.delete(:offset) || 0
      # Calculate the number of pages we need to request to get the full limit
      pages = (((limit - 1) / MAX_ITEMS_PER_PAGE) + 1)

      # Page the number of pages to a list of param hashes with pagination
      # values for limit and offset
      pages.times.map do |page|
        this_page_size = [limit - (page * MAX_ITEMS_PER_PAGE), MAX_ITEMS_PER_PAGE].min
        this_offest = offset + (page * MAX_ITEMS_PER_PAGE)
        params.merge(limit: this_page_size, offset: this_offest)
      end
    end

    def workspaces(**params)
      get_items('/workspaces', params: params)
    end

    def workspace_search(workspace_id = self.workspace_id, **params)
      get_items("/workspaces/#{workspace_id}/search", params: params)
    end

    def faceted_search(**params)
      get_items('/faceted-search', params: params, post: true)
    end

    # Returns an item whose name matches the `name` parameter.
    def find_by_name(name, **params)
      params.merge!(query: name, limit: MAX_ITEMS)
      items = workspace_search(**params).select { |item| item['name'] == name }
      raise "#{items.count} items found with name '#{name}'" if items.count > 1
      items.first
    end

    def webhooks(**params)
      get_items("/networks/#{workspace['network']['id']}/webhooks", params: params)
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
          filename: Faraday::FilePart.new(filepath, content_type, nil,
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

    def move_assets(asset_ids: [], folder_id:)
      post "/assets/move", params: { assetIds: asset_ids, folderId: folder_id }
    end

    def asset_stream_url(asset_id, type: "hls")
      type = type.downcase
      raise ArgumentError, "Invalid value for parameter type. Expected one of hls, video-3g, or video-sd, but '#{type}' was given" unless %w[hls video-3g video-sd].include?(type)

      stream_name = "#{asset_id}-stream"
      expire_date = DateTime.now.next_day.iso8601
      resp = post("/assets/#{asset_id}/streams", params: { streams: [{ name: stream_name, expirationDate: expire_date }] }, headers: { "Content-Type" => "application/json" })
      resp["complete"].first["streams"].find { |s| s["type"] == type }["url"] if resp && resp["complete"]
    end

    def workspace_contents(workspace_id = self.workspace_id, **params)
      get_items("/workspaces/#{workspace_id}/contents", params: params.merge(limit: MAX_ITEMS))
    end

    def folder(folder_id)
      get "/folders/#{folder_id}"
    end

    def folder_contents(folder_id, depth: MAX_RECURSION, current_depth: 0, **params)
      raise MaxRecursionError, "MAX_RECURSIION level #{MAX_RECURSION} exceeded" if current_depth >= MAX_RECURSION
      contents = get_items("/folders/#{folder_id}/contents", params: params.merge(limit: MAX_ITEMS))

      if current_depth < depth
        contents.each do |item|
          if item['kind'].downcase == 'folder'
            item['contents'] = folder_contents(
              item['id'],
              depth: depth,
              current_depth: (current_depth + 1),
              **params
            )
          end
        end
      end
    end

    private

    def send_request(http_method, path, params: {}, headers: {})
      @response = nil # reset the last response explicitly in case of error.
      conn.authorization :Bearer, access_token
      @response = conn.send(http_method, path, camelize_params(**params), headers)
      @response.body
    rescue StandardError => e
      raise Error.create_from(e)
    end

    # Class methods
    class << self
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
