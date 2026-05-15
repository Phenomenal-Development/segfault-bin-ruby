# frozen_string_literal: true

require "logger"

RSpec.describe SegfaultBin::LogCapture::Sink do
  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.dsn = "https://token@bin.example.com/api/events"
      c.environment = "production"
      c.send_logs = true
      c.log_min_level = :info
      c.log_source = "rails"
    end
  end

  let(:batcher) { instance_double(SegfaultBin::LogCapture::Batcher, enqueue: nil) }
  subject(:sink) { described_class.new(config, batcher: batcher) }

  it "enqueues entries at or above min_level" do
    expect(batcher).to receive(:enqueue) do |entry|
      expect(entry[:level]).to eq "warn"
      expect(entry[:message]).to eq "something happened"
      expect(entry[:environment]).to eq "production"
      expect(entry[:source]).to eq "rails"
    end
    sink.add(::Logger::WARN, "something happened")
  end

  it "drops entries below min_level" do
    expect(batcher).not_to receive(:enqueue)
    sink.add(::Logger::DEBUG, "noisy")
  end

  it "skips entirely when logs are disabled" do
    config.send_logs = false
    expect(batcher).not_to receive(:enqueue)
    sink.add(::Logger::ERROR, "boom")
  end

  it "formats exceptions" do
    expect(batcher).to receive(:enqueue) do |entry|
      expect(entry[:message]).to eq "RuntimeError: nope"
    end
    sink.add(::Logger::ERROR, RuntimeError.new("nope"))
  end

  it "tags entries with request_id from CurrentRequest.env" do
    SegfaultBin::CurrentRequest.env = { "action_dispatch.request_id" => "req-42" }
    expect(batcher).to receive(:enqueue) do |entry|
      expect(entry[:request_id]).to eq "req-42"
    end
    sink.add(::Logger::INFO, "hi")
  ensure
    SegfaultBin::CurrentRequest.reset
  end

  it "returns true so BroadcastLogger keeps broadcasting" do
    expect(sink.add(::Logger::INFO, "x")).to be true
  end
end
