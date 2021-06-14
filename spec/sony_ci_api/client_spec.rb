require 'spec_helper'
require 'webmock/rspec'

def stub_request_and_call_block(http_method, path, with: {}, stub_response: {})
  url = URI.join(SonyCiApi::Client::BASE_URL, path)
  WebMock.stub_request(http_method, url).with(**with).to_return(**stub_response)
  return_val = yield
  expect(WebMock).to have_requested(http_method, url).with(**with)
  return_val
end

RSpec.describe SonyCiApi::Client do
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
  let(:mock_access_token) { 'lasdkfjsakfjdsaljk' }
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
            'User-Agent' => 'Faraday v1.3.0'
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
      # TODO: add error codes and messages to exceptions for clearer messaging.
      context 'when a 404 is returned' do
        let(:response_status) { 404 }
        let(:response_body) { { 'code' => 'FooNotFound', 'message' => 'Foo not found.' } }
        it 'raises a NotFound error with SonyCi error code and message' do
          expect { get_result }.to raise_error Faraday::ResourceNotFound, /#{response_body['code']}.*#{response_body['message']}/
        end
      end

      context 'when a 401 is returned' do
        let(:response_status) { 401 }
        it 'raises a Unauthorized error' do
          expect { get_result }.to raise_error Faraday::UnauthorizedError
        end
      end

      context 'when a 400 is returned' do
        let(:response_status) { 400 }
        let(:response_body) { { 'code' => 'YouAreDoingItWrong', 'message' => 'That was a baaaaaad request.' } }
        it 'raises a BadRequest error with SonyCi error code and message' do
          expect { get_result }.to raise_error Faraday::BadRequestError , /#{response_body['code']}.*#{response_body['message']}/
        end
      end
    end

    describe '#workspace_search' do
      let(:workspace_id) { randstr }
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
          # here we call the method under test, indirectly because we have 2
          # ways of calling it. The return value becomes the value for
          # :workspace_search.
          call_workspace_search
        end
      end

      it 'returns the list of items' do
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
  end
end
