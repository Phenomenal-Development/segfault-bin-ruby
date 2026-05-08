# frozen_string_literal: true

RSpec.describe SegfaultBin do
  it "has a version number" do
    expect(SegfaultBin::VERSION).not_to be_nil
  end

  describe ".report" do
    let(:dsn) { "https://abc123@bin.example.com/api/events" }

    before do
      SegfaultBin.configure do |c|
        c.dsn = dsn
        c.environment = "production"
        c.send_default_pii = false
        c.async = false
      end
    end

    it "delivers payload to the configured endpoint" do
      stub = stub_request(:post, "https://bin.example.com/api/events")
        .with(headers: {"Authorization" => "Bearer abc123"})
        .to_return(status: 200, body: "")

      begin
        raise "boom"
      rescue => e
        SegfaultBin.report(e)
      end

      expect(stub).to have_been_requested
    end

    it "is silenced when rate-limiter throttles" do
      allow(SegfaultBin.rate_limiter).to receive(:throttled?).and_return(true)
      stub = stub_request(:post, /bin.example.com/)
      SegfaultBin.report(StandardError.new("x"))
      expect(stub).not_to have_been_requested
    end
  end
end
