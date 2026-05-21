# frozen_string_literal: true

require "rack"

RSpec.describe SegfaultBin::NPlusOnePayloadBuilder do
  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.environment = "production"
      c.release = "abc123"
      c.server_name = "host-1"
    end
  end

  let(:call_site) { {abs_path: "/app/c.rb", filename: "c.rb", lineno: 42, function: "show", in_app: true} }

  let(:preceding) do
    SegfaultBin::NPlusOne::Tracker::Preceding.new(
      fingerprint: "select * from users",
      sql: "SELECT * FROM users",
      duration_ms: 5.1
    )
  end

  let(:samples) do
    [
      SegfaultBin::NPlusOne::Tracker::Sample.new(sql: "SELECT * FROM posts WHERE user_id = 7", duration_ms: 1.2),
      SegfaultBin::NPlusOne::Tracker::Sample.new(sql: "SELECT * FROM posts WHERE user_id = 8", duration_ms: 1.4)
    ]
  end

  let(:group) do
    SegfaultBin::NPlusOne::Tracker::Group.new(
      fingerprint: "select * from posts where user_id = ?",
      call_site: call_site,
      count: 17,
      total_duration_ms: 184.6,
      sample_sql: "SELECT * FROM posts WHERE user_id = 7",
      samples: samples,
      first_seen_at: Time.utc(2026, 5, 9, 12, 0, 0),
      last_seen_at: Time.utc(2026, 5, 9, 12, 0, 1),
      triggered: true,
      preceding_query: preceding
    )
  end

  describe "#build" do
    subject(:payload) { described_class.new([group], false, config).build }

    it "uses the n_plus_one_query type and warning level" do
      expect(payload[:type]).to eq "n_plus_one_query"
      expect(payload[:level]).to eq "warning"
    end

    it "includes envelope fields" do
      expect(payload).to include(:event_id, :timestamp, :sdk, :environment, :release, :server_name)
      expect(payload[:sdk]).to include(name: "segfault-bin-ruby", version: SegfaultBin::VERSION)
      expect(payload[:sdk][:config]).to be_a(Hash)
    end

    it "tags the source as n_plus_one" do
      expect(payload[:tags]).to eq(source: "n_plus_one")
    end

    it "serializes groups with count, fingerprint, call_site, durations" do
      g = payload[:groups].first
      expect(g[:fingerprint]).to eq "select * from posts where user_id = ?"
      expect(g[:count]).to eq 17
      expect(g[:total_duration_ms]).to be_within(0.001).of(184.6)
      expect(g[:call_site][:lineno]).to eq 42
      expect(g[:first_seen_at]).to eq "2026-05-09T12:00:00.000Z"
    end

    it "omits sample_sql by default" do
      expect(payload[:groups].first).not_to have_key(:sample_sql)
    end

    it "includes sample_sql when send_default_pii is true" do
      config.send_default_pii = true
      expect(payload[:groups].first[:sample_sql]).to eq "SELECT * FROM posts WHERE user_id = 7"
    end

    it "exposes groups_truncated flag" do
      truncated = described_class.new([group], true, config).build
      expect(truncated[:groups_truncated]).to be true
    end

    it "shares request data shape with PayloadBuilder" do
      env = Rack::MockRequest.env_for("/users?x=1", "REQUEST_METHOD" => "GET", "HTTP_USER_AGENT" => "rspec")
      SegfaultBin::CurrentRequest.env = env
      expect(payload[:request][:method]).to eq "GET"
      expect(payload[:request][:headers]).to include("User-Agent" => "rspec")
    end

    it "carries the transaction name when path_parameters resolved a controller/action" do
      env = Rack::MockRequest.env_for("/manage/customers")
      env["action_dispatch.request.path_parameters"] = {controller: "manage/customers", action: "index"}
      SegfaultBin::CurrentRequest.env = env
      expect(payload[:transaction]).to eq "Manage::CustomersController#index"
      expect(payload[:groups].first[:parent_span]).to eq(
        "view.process_action.action_controller - Manage::CustomersController#index"
      )
    end

    it "exposes runtime, os, and contexts" do
      expect(payload[:runtime][:name]).to eq "ruby"
      expect(payload[:runtime][:version]).to eq RUBY_VERSION
      expect(payload[:contexts][:runtime][:name]).to eq "ruby"
      expect(payload[:contexts][:os]).to be_a(Hash)
      expect(payload[:contexts][:os][:name]).not_to be_nil
    end

    it "parses browser/client_os/device from User-Agent" do
      env = Rack::MockRequest.env_for("/", "HTTP_USER_AGENT" =>
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Safari/605.1.15")
      SegfaultBin::CurrentRequest.env = env
      expect(payload[:contexts][:browser]).to eq(name: "Safari", version: "26.4")
      expect(payload[:contexts][:client_os][:name]).to eq "Mac OS X"
      expect(payload[:contexts][:device][:family]).to eq "Mac"
    end

    it "exposes request_id from action_dispatch" do
      env = Rack::MockRequest.env_for("/")
      env["action_dispatch.request_id"] = "8f88b760-d2d7-4a13-ad07-a6635cff9be3"
      SegfaultBin::CurrentRequest.env = env
      expect(payload[:request_id]).to eq "8f88b760-d2d7-4a13-ad07-a6635cff9be3"
    end

    it "includes preceding_span without sql by default" do
      preceding_in_payload = payload[:groups].first[:preceding_span]
      expect(preceding_in_payload[:fingerprint]).to eq "select * from users"
      expect(preceding_in_payload).not_to have_key(:sql)
    end

    it "exposes preceding_span sql and samples when send_default_pii is true" do
      config.send_default_pii = true
      g = payload[:groups].first
      expect(g[:preceding_span][:sql]).to eq "SELECT * FROM users"
      expect(g[:samples].size).to eq 2
      expect(g[:samples].first[:sql]).to include("user_id = 7")
    end
  end
end
