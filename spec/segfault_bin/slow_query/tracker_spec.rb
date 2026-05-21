# frozen_string_literal: true

RSpec.describe SegfaultBin::SlowQuery::Tracker do
  let(:call_site_a) { {abs_path: "/app/a.rb", filename: "a.rb", lineno: 10, function: "foo", in_app: true} }
  let(:call_site_b) { {abs_path: "/app/b.rb", filename: "b.rb", lineno: 20, function: "bar", in_app: true} }

  def record(tracker, **overrides)
    defaults = {
      fingerprint: "select * from users where id = ?",
      sql: "SELECT * FROM users WHERE id = 1",
      duration_ms: 120.0,
      allocations: 50,
      slow: true,
      heavy: false,
      call_site: call_site_a
    }
    tracker.record(**defaults.merge(overrides))
  end

  it "creates a group on first record and accumulates counters" do
    tracker = described_class.new
    3.times { record(tracker, duration_ms: 150.0, allocations: 100) }
    g = tracker.groups.first
    expect(g.count).to eq 3
    expect(g.total_duration_ms).to be_within(0.001).of(450.0)
    expect(g.max_duration_ms).to be_within(0.001).of(150.0)
    expect(g.total_allocations).to eq 300
    expect(g.max_allocations).to eq 100
  end

  it "dedupes by [fingerprint, filename, lineno]" do
    tracker = described_class.new
    record(tracker, call_site: call_site_a)
    record(tracker, call_site: call_site_a)
    record(tracker, call_site: call_site_b)
    expect(tracker.groups.size).to eq 2
  end

  it "tracks both kinds when query breaches duration AND allocations" do
    tracker = described_class.new
    record(tracker, slow: true, heavy: true)
    expect(tracker.groups.first.kinds.to_a).to contain_exactly(:slow_duration, :high_allocations)
  end

  it "carries only the heavy kind when only allocations breached" do
    tracker = described_class.new
    record(tracker, slow: false, heavy: true)
    expect(tracker.groups.first.kinds.to_a).to eq([:high_allocations])
  end

  it "caps samples at MAX_SAMPLES_PER_GROUP" do
    tracker = described_class.new
    8.times { |i| record(tracker, sql: "SELECT #{i}") }
    samples = tracker.groups.first.samples
    expect(samples.size).to eq described_class::MAX_SAMPLES_PER_GROUP
    expect(samples.first.sql).to eq "SELECT 0"
  end

  it "respects max_groups cap and reports full?" do
    tracker = described_class.new(max_groups: 2)
    record(tracker, fingerprint: "a", call_site: call_site_a)
    record(tracker, fingerprint: "b", call_site: call_site_a)
    record(tracker, fingerprint: "c", call_site: call_site_a)
    expect(tracker.full?).to be true
    expect(tracker.groups.size).to eq 2
  end

  it "keeps sample_sql as the first seen SQL for the group" do
    tracker = described_class.new
    record(tracker, sql: "SELECT 1")
    record(tracker, sql: "SELECT 2")
    expect(tracker.groups.first.sample_sql).to eq "SELECT 1"
  end
end
