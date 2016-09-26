require 'rspec/its'

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed

  config.example_status_persistence_file_path = File.expand_path("../examples.state", __FILE__)

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
    mocks.verify_partial_doubles = true
  end
end
