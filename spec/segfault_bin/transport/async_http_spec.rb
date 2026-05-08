# frozen_string_literal: true

require "logger"

RSpec.describe SegfaultBin::Transport::AsyncHttp do
  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.dsn = "https://abc123@bin.example.com/api/events"
      c.logger = Logger.new(IO::NULL)
    end
  end

  let(:transport) { described_class.new(config) }

  after { transport.shutdown }

  def wait_for(timeout: 3)
    deadline = Time.now + timeout
    until yield
      raise "wait_for timed out" if Time.now > deadline
      sleep 0.01
    end
  end

  def counting_stub(url: "https://bin.example.com/api/events", status: 200)
    counter = {value: 0, mutex: Mutex.new}
    stub_request(:post, url).to_return do |_req|
      counter[:mutex].synchronize { counter[:value] += 1 }
      {status: status}
    end
    counter
  end

  it "deliver does not block (1000 deliveries < 100ms)" do
    stub_request(:post, "https://bin.example.com/api/events").to_return(status: 200)

    elapsed = Benchmark.realtime do
      1000.times { transport.deliver({event: "x"}) }
    end

    expect(elapsed).to be < 0.1
  end

  it "worker processes the queue" do
    counter = counting_stub
    5.times { transport.deliver({event: "x"}) }
    wait_for { counter[:value] == 5 }
    expect(counter[:value]).to eq(5)
  end

  it "respects Retry-After on 429 then succeeds" do
    counter = {value: 0, mutex: Mutex.new}
    stub_request(:post, "https://bin.example.com/api/events").to_return do |_req|
      n = counter[:mutex].synchronize { counter[:value] += 1; counter[:value] }
      if n == 1
        {status: 429, headers: {"Retry-After" => "0.1"}}
      else
        {status: 200}
      end
    end

    transport.deliver({event: "x"})
    wait_for(timeout: 5) { counter[:value] >= 2 }
    expect(counter[:value]).to be >= 2
  end

  it "retries 5xx up to 3 attempts then gives up" do
    counter = counting_stub(status: 500)
    transport.deliver({event: "x"})
    sleep 0.2
    # backoff is attempt^2 + rand → 1..2s, 4..5s; just make sure we eventually hit 3
    wait_for(timeout: 12) { counter[:value] == 3 }
    sleep 0.5
    expect(counter[:value]).to eq(3)
  end

  it "does not retry on 401" do
    counter = counting_stub(status: 401)
    transport.deliver({event: "x"})
    wait_for { counter[:value] >= 1 }
    sleep 0.3
    expect(counter[:value]).to eq(1)
  end

  it "drops events when queue is full and increments drop counter" do
    stub_request(:post, "https://bin.example.com/api/events").to_return do |_req|
      sleep 5
      {status: 200}
    end

    # Worker pops one, then queue holds up to QUEUE_SIZE; further pushes drop.
    300.times { transport.deliver({event: "x"}) }

    expect(transport.instance_variable_get(:@dropped_count)).to be > 0
  end

  it "does not raise to caller when queue is full" do
    stub_request(:post, "https://bin.example.com/api/events").to_return do |_req|
      sleep 5
      {status: 200}
    end

    expect {
      300.times { transport.deliver({event: "x"}) }
    }.not_to raise_error
  end

  it "flush waits until the queue is empty" do
    counting_stub
    20.times { transport.deliver({event: "x"}) }
    transport.flush(timeout: 3)
    expect(transport.instance_variable_get(:@queue).empty?).to be true
  end

  it "shutdown stops the worker" do
    worker = transport.instance_variable_get(:@worker)
    expect(worker).to be_alive
    transport.shutdown
    expect(worker).not_to be_alive
  end

  it "shutdown is idempotent" do
    transport.shutdown
    expect { transport.shutdown }.not_to raise_error
  end
end
