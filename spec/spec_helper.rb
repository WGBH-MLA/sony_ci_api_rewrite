require "bundler/setup"
require "sony_ci_api"
require 'webmock'
require 'pry-byebug'

# Require support files
# Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    # Use WebMock to disable net connections by default. Default should be to
    # mock the API endpoints.
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  # Allow the :focus flag
  config.filter_run_when_matching :focus
end
