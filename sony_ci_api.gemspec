# frozen_string_literal: true

require_relative 'lib/sony_ci_api/version'

Gem::Specification.new do |spec|
  spec.name          = "sony_ci_api"
  spec.version       = SonyCiApi::VERSION
  spec.authors       = ["Andrew Myers"]
  spec.email         = ["andrew_myers@wgbh.org"]

  spec.summary       = "Gem for Sony Ci API"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.4.4")

  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'activesupport'
  spec.add_dependency 'faraday', '~> 1.3.0'
  spec.add_dependency 'faraday_middleware'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'webmock'
end
