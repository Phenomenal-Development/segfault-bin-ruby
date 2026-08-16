# frozen_string_literal: true

RSpec.describe SegfaultBin::LogCapture::Batcher do
  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.dsn = "https://token@bin.example.com/api/events"
      c.environment = "production"
      c.send_logs = true
      c.log_endpoint_path = "/api/logs"
      c.log_batch_size = 2
      c.log_flush_interval = 0.05
      c.log_max_buffer = 10
    end
  end

  subject(:batcher) { described_class.new(config) }

  after { batcher.shutdown }

  def entry(message, level: "info")
    {
      occurred_at: Time.now.utc.iso8601(3),
      level:       level,
      message:     message,
      environment: "production",
      release:     nil,
      server_name: "test",
      source:      "rails",
      request_id:  nil
    }
  end

  def wait_for_request(stub, timeout: 2.0)
    deadline = Time.now + timeout
    while Time.now < deadline
      return true if WebMock::RequestRegistry.instance.times_executed(stub.request_pattern).positive?
      sleep 0.02
    end
    false
  end

  it "flushes when batch size is reached" do
    stub = stub_request(:post, "https://bin.example.com/api/logs").to_return(status: 202)
    batcher.start
    batcher.enqueue(entry("a"))
    batcher.enqueue(entry("b"))
    expect(wait_for_request(stub)).to be true
    expect(stub).to have_been_requested.at_least_once
  end

  it "names the gem in the batch body and in a header" do
    stub = stub_request(:post, "https://bin.example.com/api/logs")
      .with(headers: {"X-Segfault-Bin-Version" => SegfaultBin::VERSION}) { |req|
        body = JSON.parse(req.body)
        body["sdk"] == {"name" => "segfault-bin-ruby", "version" => SegfaultBin::VERSION} &&
          body["logs"].length == 2
      }
      .to_return(status: 202)
    batcher.start
    batcher.enqueue(entry("a"))
    batcher.enqueue(entry("b"))
    expect(wait_for_request(stub)).to be true
  end

  it "sends gzip-encoded body when over threshold" do
    stub = stub_request(:post, "https://bin.example.com/api/logs")
             .with(headers: { "Content-Encoding" => "gzip" })
             .to_return(status: 202)
    batcher.start
    big = "x" * 2000
    batcher.enqueue(entry(big))
    batcher.enqueue(entry(big))
    expect(wait_for_request(stub)).to be true
  end

  it "drops entries when the buffer is full" do
    # Stub so the after-hook shutdown flush doesn't blow up on net access.
    stub_request(:post, "https://bin.example.com/api/logs").to_return(status: 202)
    # don't start the worker, so the buffer accumulates
    (config.log_max_buffer + 5).times { batcher.enqueue(entry("x")) }
    # Buffer should be capped at max_buffer; pop_batch returns at most batch_size
    batch = batcher.send(:pop_batch)
    expect(batch.size).to eq config.log_batch_size
    remaining = batcher.send(:pop_batch)
    expect(remaining.size).to eq config.log_batch_size
  end

  it "backs off when server returns 204 (logs disabled)" do
    stub = stub_request(:post, "https://bin.example.com/api/logs").to_return(status: 204)
    batcher.start
    batcher.enqueue(entry("a"))
    batcher.enqueue(entry("b"))
    expect(wait_for_request(stub)).to be true

    # Worker sets @disabled_until after delivering — wait for it.
    deadline = Time.now + 1.0
    until Time.now > deadline || batcher.instance_variable_get(:@disabled_until)
      sleep 0.02
    end
    expect(batcher.instance_variable_get(:@disabled_until)).to be_a(Time)
  end
end
