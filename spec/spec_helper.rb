# frozen_string_literal: true

require "benchmark"
require "webmock/rspec"
require "segfault_bin"

WebMock.disable_net_connect!(allow_localhost: false)

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    SegfaultBin.reset!
    SegfaultBin::CurrentRequest.reset
  end
end
