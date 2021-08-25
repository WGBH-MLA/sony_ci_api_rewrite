RSpec.describe SonyCiApi::Error do
  describe '.create_from' do
    context 'for rando errors that we have not explicitly mapped' do
      let(:orig_error) { Class.new(StandardError).new }
      it 'returns a SonyCiApi::Error instance' do
        expect(described_class.create_from(orig_error).class).to eq SonyCiApi::Error
      end
    end

    context 'with Faraday errors' do
      let(:expected_mappings) {
        {
          Faraday::ClientError               => SonyCiApi::ClientError,
          Faraday::BadRequestError           => SonyCiApi::BadRequestError,
          Faraday::UnauthorizedError         => SonyCiApi::UnauthorizedError,
          Faraday::ForbiddenError            => SonyCiApi::ForbiddenError,
          Faraday::ResourceNotFound          => SonyCiApi::NotFoundError,
          Faraday::ProxyAuthError            => SonyCiApi::ProxyAuthError,
          Faraday::ConflictError             => SonyCiApi::ConflictError,
          Faraday::UnprocessableEntityError  => SonyCiApi::UnprocessableEntityError,
          Faraday::ServerError               => SonyCiApi::ServerError,
          Faraday::TimeoutError              => SonyCiApi::TimeoutError,
          Faraday::NilStatusError            => SonyCiApi::NilStatusError,
          Faraday::ConnectionFailed          => SonyCiApi::ConnectionFailed,
          Faraday::SSLError                  => SonyCiApi::SSLError
        }
      }

      it 'maps to corresponding subclasses of SonyCiApi::Error' do
        expected_mappings.each do |faraday_error_class, expected_error_class|
          # Create an instance of the Faraday error class. Use nil message and
          # empty response because we don't need those, but Faraday classes do.
          faraday_error = faraday_error_class.new(nil, {})
          new_error = described_class.create_from(faraday_error_class.new(nil, {}))
          expect(new_error).to be_a expected_error_class
        end
      end
    end
  end

  describe '#json_hash' do
    let(:msg) { rand.to_s }
    let(:from_error_class) { Class.new(StandardError) }
    let(:from_error) { from_error_class.new(msg) }
    subject { described_class.new(from_error: from_error) }

    it 'returns a hash of error info that can be used in JSON response' do
      expect(subject.to_h).to eq(
        {
          "error" => described_class.to_s,
          "error_message" => msg,
          "from_error" => from_error_class.to_s
        }
      )
    end
  end
end
