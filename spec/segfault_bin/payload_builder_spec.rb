# frozen_string_literal: true

require "rack"

RSpec.describe SegfaultBin::PayloadBuilder do
  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.environment = "production"
      c.release = "abc123"
      c.server_name = "host-1"
    end
  end

  let(:exception) do
    raise ArgumentError, "bad arg"
  rescue => e
    e
  end

  describe "#build" do
    subject(:payload) do
      described_class.new(exception, context, config).build
    end

    let(:context) { {severity: "error", handled: false, source: "application"} }

    it "produces schema" do
      expect(payload).to include(
        :event_id, :timestamp, :platform, :sdk, :exception, :tags
      )
      expect(payload[:platform]).to eq "ruby"
      expect(payload[:sdk]).to include(name: "segfault-bin-ruby", version: SegfaultBin::VERSION)
      expect(payload[:sdk][:config]).to be_a(Hash)
      expect(payload[:level]).to eq "error"
      expect(payload[:environment]).to eq "production"
      expect(payload[:release]).to eq "abc123"
      expect(payload[:server_name]).to eq "host-1"
    end

    it "includes a UUID event_id and ISO8601 timestamp" do
      expect(payload[:event_id]).to match(/\A[\h-]{36}\z/)
      expect(payload[:timestamp]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
    end

    it "builds the exception block with type/value/frames" do
      expect(payload[:exception]).to include(type: "ArgumentError", value: "bad arg")
      expect(payload[:exception][:frames]).to be_an(Array)
      expect(payload[:exception][:frames]).not_to be_empty
    end

    it "surfaces handled/source in tags" do
      expect(payload[:tags]).to include(handled: false, source: "application")
    end

    it "maps unknown severity levels to 'error'" do
      payload = described_class.new(exception, {severity: "weird"}, config).build
      expect(payload[:level]).to eq "error"
    end
  end

  describe "#build_request" do
    let(:context) { {} }

    it "is empty when no request env is set" do
      payload = described_class.new(exception, context, config).build
      expect(payload[:request]).to eq({})
    end

    it "captures method/url/headers when CurrentRequest.env is set" do
      env = Rack::MockRequest.env_for(
        "/users?x=1",
        "REQUEST_METHOD" => "POST",
        "HTTP_USER_AGENT" => "rspec",
        "HTTP_X_REQUEST_ID" => "req-1",
        "HTTP_AUTHORIZATION" => "Bearer should-not-leak"
      )
      SegfaultBin::CurrentRequest.env = env

      payload = described_class.new(exception, context, config).build
      expect(payload[:request][:method]).to eq "POST"
      expect(payload[:request][:headers]).to include("User-Agent" => "rspec", "X-Request-Id" => "req-1")
      expect(payload[:request][:headers]).not_to have_key("Authorization")
    end

    it "scrubs sensitive params" do
      env = Rack::MockRequest.env_for(
        "/login",
        method: "POST",
        params: "user=alice&password=hunter2"
      )
      SegfaultBin::CurrentRequest.env = env

      payload = described_class.new(exception, context, config).build
      expect(payload[:request][:params]["password"]).to eq "[FILTERED]"
      expect(payload[:request][:params]["user"]).to eq "alice"
    end
  end

  describe "#build_user (hybrid)" do
    let(:context) { {user: {id: 7, email: "a@b.com", note: "ignored"}} }

    it "uses context user, whitelisted to known fields" do
      payload = described_class.new(exception, context, config).build
      expect(payload[:user]).to eq(id: 7, email: "a@b.com")
    end

    it "merges CurrentRequest.user with last-write-wins (over context)" do
      SegfaultBin::CurrentRequest.user = {id: 999, username: "alice"}
      payload = described_class.new(exception, context, config).build
      expect(payload[:user]).to include(id: 999, email: "a@b.com", username: "alice")
    end

    it "adds remote ip only when send_default_pii is true" do
      env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "203.0.113.42")
      SegfaultBin::CurrentRequest.env = env

      config.send_default_pii = false
      payload = described_class.new(exception, {}, config).build
      expect(payload[:user]).to eq({})

      config.send_default_pii = true
      payload = described_class.new(exception, {}, config).build
      expect(payload[:user]).to eq(ip_address: "203.0.113.42")
    end
  end
end
