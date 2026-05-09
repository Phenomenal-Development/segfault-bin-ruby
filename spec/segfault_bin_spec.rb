# frozen_string_literal: true

require "rack"
require "json"
require "active_support/gzip"

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

  describe "N+1 detection (integration)" do
    let(:dsn) { "https://abc123@bin.example.com/api/events" }

    def configure!(detect:)
      SegfaultBin.configure do |c|
        c.dsn = dsn
        c.environment = "production"
        c.async = false
        c.detect_n_plus_one = detect
        c.n_plus_one_threshold = 3
      end
    end

    def fire_query
      ActiveSupport::Notifications.instrument(
        "sql.active_record",
        sql: "SELECT * FROM users WHERE id = #{rand(100)}",
        name: "User Load",
        cached: false
      )
    end

    def run_middleware(app)
      env = Rack::MockRequest.env_for("/")
      mw = SegfaultBin::Middleware::CaptureRequest.new(app)
      mw.call(env)
    end

    it "emits an n_plus_one_query event when threshold is reached" do
      configure!(detect: true)
      stub = stub_request(:post, "https://bin.example.com/api/events")
        .with { |req|
          raw = req.headers["Content-Encoding"] == "gzip" ? ActiveSupport::Gzip.decompress(req.body) : req.body
          body = JSON.parse(raw)
          body["type"] == "n_plus_one_query" &&
            body["groups"].is_a?(Array) &&
            body["groups"].first["count"] >= 3
        }
        .to_return(status: 200, body: "")

      run_middleware(->(_e) {
        3.times { fire_query }
        [200, {}, ["ok"]]
      })

      expect(stub).to have_been_requested
    end

    it "does not emit when below threshold" do
      configure!(detect: true)
      stub = stub_request(:post, /bin.example.com/)

      run_middleware(->(_e) {
        2.times { fire_query }
        [200, {}, ["ok"]]
      })

      expect(stub).not_to have_been_requested
    end

    it "does not subscribe when detect_n_plus_one is false" do
      configure!(detect: false)
      stub = stub_request(:post, /bin.example.com/)
      expect(SegfaultBin::NPlusOne::Subscriber.attached?).to be false

      run_middleware(->(_e) {
        5.times { fire_query }
        [200, {}, ["ok"]]
      })

      expect(stub).not_to have_been_requested
    end
  end
end
