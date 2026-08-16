# frozen_string_literal: true

RSpec.describe SegfaultBin::Transport::SyncHttp do
  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.dsn = "https://abc123@bin.example.com/api/events"
    end
  end

  it "POSTs JSON with bearer auth and protocol header" do
    stub = stub_request(:post, "https://bin.example.com/api/events")
      .with(
        headers: {
          "Authorization" => "Bearer abc123",
          "Content-Type" => "application/json",
          "X-Segfault-Bin-Protocol" => "1",
          "X-Segfault-Bin-Version" => SegfaultBin::VERSION,
          "User-Agent" => "segfault-bin-ruby/#{SegfaultBin::VERSION}"
        }
      )
      .to_return(status: 200)

    described_class.new(config).deliver(event_id: "abc", message: "hi")

    expect(stub).to have_been_requested
  end

  it "gzips bodies larger than 1KB and sets Content-Encoding" do
    stub = stub_request(:post, "https://bin.example.com/api/events")
      .with(headers: {"Content-Encoding" => "gzip"}) { |req|
        decompressed = ActiveSupport::Gzip.decompress(req.body)
        JSON.parse(decompressed)["payload"].length > 1024
      }
      .to_return(status: 200)

    described_class.new(config).deliver(payload: "x" * 2000)

    expect(stub).to have_been_requested
  end

  it "does not set Content-Encoding for small bodies" do
    stub = stub_request(:post, "https://bin.example.com/api/events")
      .with { |req| !req.headers.key?("Content-Encoding") }
      .to_return(status: 200)

    described_class.new(config).deliver(small: "ok")

    expect(stub).to have_been_requested
  end
end
