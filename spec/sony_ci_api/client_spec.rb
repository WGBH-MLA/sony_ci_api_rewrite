require 'spec_helper'
require 'webmock/rspec'

# Stubs a request, calls the passed block, and then runs an expectation on
# the stubbed request (a commonly repeated API test pattern).
# @return the return value of the block.
def stub_request_and_call_block(http_method, path, with: {}, stub_response: {})
  url = URI.join(SonyCiApi::Client::BASE_URL, path)
  stub = WebMock.stub_request(http_method, url)
  stub.with(**with) unless with.empty?
  stub.to_return(**stub_response) unless stub_response.empty?
  # Call the block and save the return val to return from this method.
  return_val = yield
  expectation = have_requested(http_method, url)
  expectation.with(**with) unless with.empty?
  expect(WebMock).to expectation
  return_val
end

RSpec.describe SonyCiApi::Client do

  def randhex(len=32)
    len.times.map { rand(15).to_s(16) }.join
  end

  def randstr(len=6)
    @chars ||= [ ('a'..'z').to_a, ('A'..'Z').to_a, ('0'..'9').to_a ].flatten
    Array.new(len.to_i) { @chars.sample }.join
  end

  # Local helper
  def camelize_params(**params)
    SonyCiApi::Client.camelize_params(**params)
  end

  let(:base_url) { SonyCiApi::Client::BASE_URL }

  let(:username) { randstr }
  let(:password) { randstr }
  let(:encoded_username_and_password) { Base64.encode64("#{username}:#{password}").strip }
  let(:client_id) { randstr }
  let(:client_secret) { randstr }

  let(:client) {
    described_class.new( username: username,
                         password: password,
                         client_id: client_id,
                         client_secret: client_secret )
  }

  # Request params for authentication request
  let(:mock_access_token) { randhex }
  let(:response_body) { { "fooBarResponse" => randstr } }
  let(:response_status) { 200 }

  describe '#access_token' do
    let(:access_token) do
      stub_request_and_call_block(
        :post,
        '/oauth2/token',
        with: {
          body: {
            grant_type: 'password',
            client_id: client_id,
            client_secret: client_secret
          }.to_json,
          headers: {
            'Accept' => '*/*',
            'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
            'Authorization' => "Basic #{encoded_username_and_password}",
            'Content-Type' => 'application/json',
            'User-Agent' => "Faraday v#{Faraday::VERSION}"
          }
        },
        stub_response: {
          body: { 'access_token' => mock_access_token }.to_json,
          status: '200'
        }
      ) do
        client.access_token
      end
    end


    it 'fetches the access token for use in subsequent requests' do
      expect(access_token).to eq mock_access_token
    end
  end

  context 'with a valid access token' do
    before { allow(client).to receive(:access_token).and_return(mock_access_token) }

    describe '#get' do
      let(:response_status) { 200 }
      let(:response_body) { { "fooBarResponse" => randstr } }

      # The return value of SonyCiApi::Client#get.
      let(:get_result) {
        stub_request_and_call_block(
          :get,
          "#{base_url}/foo/bar",
          with: {
            query: { "fooBar" => "bar" },
            headers: {
              'Foo-Header' => 'foo/header'
            }
          },
          stub_response: {
            status: response_status,
            body: response_body.to_json,
          }
        ) do
          client.get(
            "foo/bar",
            params: { foo_bar: "bar" },
            headers: { foo_header: "foo/header" }
          )
        end
      }

      it 'returns parsed JSON response' do
        expect(get_result).to eq response_body
      end

      describe '#response after calling #get' do
        it 'returns the whole response object from the most recent request' do
          expect(get_result).to eq client.response.body
          expect(client.response).to be_a Faraday::Response
        end
      end

      # ERROR CASES
      # Ensure proper errors are returned for each HTTP error code.
      describe 'Error Cases' do
        context 'when a 400 is returned' do
          let(:response_status) { 400 }
          it 'raises a SonyCiApi::Error with SonyCi error code and message' do
            expect { get_result }.to raise_error SonyCiApi::ClientError
          end
        end

        context 'when a 401 is returned' do
          let(:response_status) { 401 }
          it 'raises a Unauthorized error' do
            expect { get_result }.to raise_error SonyCiApi::UnauthorizedError
          end
        end

        context 'when a 403 is returned' do
          let(:response_status) { 403 }
          it 'raises a NotFoundError error' do
            expect { get_result }.to raise_error SonyCiApi::ForbiddenError
          end
        end

        context 'when a 404 is returned' do
          let(:response_status) { 404 }
          it 'raises a NotFoundError error' do
            expect { get_result }.to raise_error SonyCiApi::NotFoundError
          end
        end

        context 'when a 407 is returned' do
          let(:response_status) { 407 }
          it 'raises a ProxyAuthError error' do
            expect { get_result }.to raise_error SonyCiApi::ProxyAuthError
          end
        end

        context 'when a 409 is returned' do
          let(:response_status) { 409 }
          it 'raises a ConflictError error' do
            expect { get_result }.to raise_error SonyCiApi::ConflictError
          end
        end

        context 'when a 422 is returned' do
          let(:response_status) { 422 }
          it 'raises a UnprocessableEntity error' do
            expect { get_result }.to raise_error SonyCiApi::UnprocessableEntityError
          end
        end

        context 'when a 500 is returned' do
          let(:response_status) { 500 }
          it 'raises a UnprocessableEntity error' do
            expect { get_result }.to raise_error SonyCiApi::ServerError
          end
        end
      end
    end

    describe 'workspaces' do
      # In reality, the hashes representing workspaces are much more extensive.
      # For testing we can use a minimal and arbitrary data structure.
      let(:expected_workspaces) { [
          { "id" => "foo", "name" => "Foo Workspace" },
          { "id" => "bar", "name" => "Bar Workspace" }
      ] }

      let(:actual_workspaces) {
        stub_request_and_call_block(
          :get,
          "#{base_url}/workspaces",
          stub_response: {
            # Pared down response; we are only testing to see if #workspaces returns
            # the 'items' property of the reponse.
            body: { "items": expected_workspaces }.to_json,
            status: response_status
          }
        ) do
          # Call and return #workspaces as value for actual_workspaces helper.
          client.workspaces
        end
      }

      it 'returns a list of hashes representing each workspace' do
        expect(actual_workspaces).to eq expected_workspaces
      end
    end

    describe '#workspace_search' do
      let(:workspace_id) { randhex }
      let(:params) { { query: '', kind: '', limit: '', offset: '', order_by: '',
                       order_direction: '', fields: '' } }
      let(:response_body) {
        {
          'items' => [
            { 'name' => 'foo'},
            { 'name' => 'bar' }
          ]
        }
      }

      # This actually calls the method under test, but we want to do it in
      # more than one way (see call_workspace_search elsewhere).
      let(:call_workspace_search) { client.workspace_search(workspace_id, **params) }

      let(:workspace_search) do
        stub_request_and_call_block(
          :get,
          "#{base_url}/workspaces/#{workspace_id}/search",
          with: {
            query: camelize_params(params)
          },
          stub_response: {
            body: response_body.to_json,
            status: response_status
          }
        ) do
          call_workspace_search
        end
      end

      it 'returns the list of items,' do
        expect(workspace_search).to eq response_body['items']
      end

      context 'with a default workspace_id' do
        before { client.workspace_id = workspace_id }
        # Here, we call the method without specifying a workspace ID in order
        # to test that the default workspace_id was used.
        let(:call_workspace_search) { client.workspace_search(**params) }
        it 'returns the list of itmes for ' do
          expect(workspace_search).to eq response_body['items']
        end
      end
    end

    describe '#asset' do
      let(:asset_id) { randhex }
      # Pared down response body. In reality it's much bigger.
      let(:response_body) { { "id" => asset_id, "name" => "foovie.mp4" } }
      let(:asset) {
        stub_request_and_call_block(
          :get,
          "#{base_url}/assets/#{asset_id}",
          stub_response: {
            body: response_body.to_json,
            status: response_status
          }
        ) do
          # Call the method under test
          client.asset(asset_id)
        end
      }

      it 'returns the asset hash' do
        expect(asset).to eq response_body
      end

      context 'with an asset id that cannot be found,' do
        let(:response_status) { 404 }
        it 'raises a SonyCiApi::NotFound error' do
          expect { asset }.to raise_error SonyCiApi::NotFoundError
        end
      end
    end

    describe '#asset_download' do
      let(:asset_id) { randhex }
      let(:response_body) {
        {
          'id' => asset_id,
          'location' => randstr
        }
      }

      let(:asset_download_info) {
        stub_request_and_call_block(
          :get,
          "#{base_url}/assets/#{asset_id}/download",
          stub_response: {
            body: response_body.to_json,
            status: response_status
          }
        ) do
          # Call the method under test
          client.asset_download(asset_id)
        end
      }

      it 'returns download information for an asset' do
        expect(asset_download_info).to eq response_body
      end
    end
  end

  describe '#load_config!' do
    let(:config_hash) {
      {
        username: randstr,
        password: randstr,
        workspace_id: randhex,
        client_id: randhex,
        client_secret: randhex
      }
    }

    let(:config_hash_with_erb) {
      {
        username: "<%= TestCredentials.config_hash[:username] %>",
        password: "<%= TestCredentials.config_hash[:password] %>",
        workspace_id: "<%= TestCredentials.config_hash[:workspace_id] %>",
        client_id: "<%= TestCredentials.config_hash[:client_id] %>",
        client_secret: "<%= TestCredentials.config_hash[:client_secret] %>"
      }
    }

    # Create some temp files for use in the specs.
    let(:valid_config_file) { Tempfile.new }
    let(:valid_config_file_erb) { Tempfile.new }
    let(:invalid_config_file) { Tempfile.new }

    before do
      # Write to the temp files used in the specs
      valid_config_file.write(config_hash.to_yaml) && valid_config_file.rewind
      valid_config_file_erb.write(config_hash_with_erb.to_yaml) && valid_config_file_erb.rewind
      invalid_config_file.write(':') && invalid_config_file.rewind

      # Create some dummy class available in a global scope that can be
      # recognized by ERB within SonyCiApi::Client#load_config!
      class TestCredentials
        def self.config_hash
          @config_hash ||= {
            username: rand(9999).to_s,
            password: rand(9999).to_s,
            workspace_id: rand(9999).to_s,
            client_id: rand(9999).to_s,
            client_secret: rand(9999).to_s
          }
        end
      end
    end

    after do
      # close and delete the tmp files used in the specs.
      valid_config_file.close && valid_config_file.unlink
      valid_config_file_erb.close && valid_config_file_erb.unlink
      invalid_config_file.close && invalid_config_file.unlink

      # Destroy our FakeCredentials object.
      Object.send(:remove_const, :TestCredentials)
    end

    context 'with a valid YAML config file' do
      it 'loads config from the YAML file' do
        expect { client.load_config!(valid_config_file.path) }.not_to raise_error
        expect(client.config).to eq config_hash
      end
    end

    context 'with a valid YAML config file that uses ERB' do
      it 'loads config from the YAML file' do
        expect { client.load_config!(valid_config_file_erb.path) }.not_to raise_error
        expect(client.config).to eq TestCredentials.config_hash
      end
    end

    context 'with a config hash' do
      it 'uses the config hash' do
        expect { client.load_config!(config_hash) }.not_to raise_error
        expect(client.config).to eq config_hash
      end
    end

    context 'with a non-YAML file' do
      it 'raises an error' do
        expect { client.load_config!(invalid_config_file.path) }.to raise_error SonyCiApi::InvalidConfigError
      end
    end

    context 'with things that are not hashes for existing files' do
      it 'raises an InvalidConfigError' do
        ["not a file", Object.new, 123, Array.new ].each do |invalid_config|
          expect { client.load_config!(invalid_config) }.to raise_error SonyCiApi::InvalidConfigError
        end
      end
    end
  end
end
