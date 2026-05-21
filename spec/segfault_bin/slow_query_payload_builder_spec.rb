# frozen_string_literal: true

require "set"
require "rack"

RSpec.describe SegfaultBin::SlowQueryPayloadBuilder do
  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.environment = "production"
      c.release = "abc123"
      c.server_name = "host-1"
    end
  end

  let(:call_site) { {abs_path: "/app/c.rb", filename: "c.rb", lineno: 42, function: "show", in_app: true} }

  let(:samples) do
    [
      SegfaultBin::SlowQuery::Tracker::Sample.new(sql: "SELECT * FROM posts WHERE id = 7", duration_ms: 120.0, allocations: 15_000),
      SegfaultBin::SlowQuery::Tracker::Sample.new(sql: "SELECT * FROM posts WHERE id = 8", duration_ms: 130.0, allocations: 16_000)
    ]
  end

  let(:group) do
    SegfaultBin::SlowQuery::Tracker::Group.new(
      fingerprint: "select * from posts where id = ?",
      call_site: call_site,
      count: 2,
      total_duration_ms: 250.0,
      max_duration_ms: 130.0,
      total_allocations: 31_000,
      max_allocations: 16_000,
      kinds: Set.new([:slow_duration, :high_allocations]),
      sample_sql: "SELECT * FROM posts WHERE id = 7",
      samples: samples,
      first_seen_at: Time.utc(2026, 5, 21, 12, 0, 0),
      last_seen_at: Time.utc(2026, 5, 21, 12, 0, 1)
    )
  end

  describe "#build" do
    subject(:payload) { described_class.new([group], false, config).build }

    it "uses the slow_query type and warning level" do
      expect(payload[:type]).to eq "slow_query"
      expect(payload[:level]).to eq "warning"
    end

    it "tags the source as slow_query" do
      expect(payload[:tags]).to eq(source: "slow_query")
    end

    it "serializes group counters and stats" do
      g = payload[:groups].first
      expect(g[:fingerprint]).to eq "select * from posts where id = ?"
      expect(g[:count]).to eq 2
      expect(g[:total_duration_ms]).to be_within(0.001).of(250.0)
      expect(g[:max_duration_ms]).to be_within(0.001).of(130.0)
      expect(g[:total_allocations]).to eq 31_000
      expect(g[:max_allocations]).to eq 16_000
    end

    it "serializes kinds as strings" do
      expect(payload[:groups].first[:kinds]).to contain_exactly("slow_duration", "high_allocations")
    end

    it "omits sample_sql by default" do
      expect(payload[:groups].first).not_to have_key(:sample_sql)
      expect(payload[:groups].first).not_to have_key(:samples)
    end

    it "includes sample_sql and samples when send_default_pii is true" do
      config.send_default_pii = true
      g = payload[:groups].first
      expect(g[:sample_sql]).to eq "SELECT * FROM posts WHERE id = 7"
      expect(g[:samples].size).to eq 2
      expect(g[:samples].first).to include(:sql, :duration_ms, :allocations)
    end

    it "exposes groups_truncated flag" do
      truncated = described_class.new([group], true, config).build
      expect(truncated[:groups_truncated]).to be true
    end

    it "includes envelope fields" do
      expect(payload).to include(:event_id, :timestamp, :sdk, :environment, :release, :server_name)
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
  end
end
