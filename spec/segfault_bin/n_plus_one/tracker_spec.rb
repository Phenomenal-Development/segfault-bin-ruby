# frozen_string_literal: true

RSpec.describe SegfaultBin::NPlusOne::Tracker do
  let(:call_site_a) { {abs_path: "/app/a.rb", filename: "a.rb", lineno: 10, function: "foo", in_app: true} }
  let(:call_site_b) { {abs_path: "/app/b.rb", filename: "b.rb", lineno: 20, function: "bar", in_app: true} }

  it "does not trigger below threshold" do
    tracker = described_class.new(threshold: 5)
    4.times { tracker.record(fingerprint: "select", sql: "SELECT 1", duration_ms: 1.0, call_site: call_site_a) }
    expect(tracker.triggered_groups).to be_empty
  end

  it "triggers exactly once at threshold and keeps counting after" do
    tracker = described_class.new(threshold: 3)
    7.times { tracker.record(fingerprint: "select", sql: "SELECT 1", duration_ms: 0.5, call_site: call_site_a) }
    expect(tracker.triggered_groups.size).to eq 1
    g = tracker.triggered_groups.first
    expect(g.count).to eq 7
    expect(g.total_duration_ms).to be_within(0.001).of(3.5)
  end

  it "splits same fingerprint by call site" do
    tracker = described_class.new(threshold: 2)
    2.times { tracker.record(fingerprint: "select", sql: "SELECT 1", duration_ms: 1.0, call_site: call_site_a) }
    2.times { tracker.record(fingerprint: "select", sql: "SELECT 1", duration_ms: 1.0, call_site: call_site_b) }
    expect(tracker.triggered_groups.size).to eq 2
  end

  it "respects max_groups cap" do
    tracker = described_class.new(threshold: 1, max_groups: 2)
    tracker.record(fingerprint: "a", sql: "A", duration_ms: 1.0, call_site: call_site_a)
    tracker.record(fingerprint: "b", sql: "B", duration_ms: 1.0, call_site: call_site_a)
    tracker.record(fingerprint: "c", sql: "C", duration_ms: 1.0, call_site: call_site_a)
    expect(tracker.full?).to be true
    expect(tracker.triggered_groups.size).to eq 2
  end

  it "keeps the first sample SQL for the group" do
    tracker = described_class.new(threshold: 2)
    tracker.record(fingerprint: "select", sql: "SELECT 1", duration_ms: 1.0, call_site: call_site_a)
    tracker.record(fingerprint: "select", sql: "SELECT 2", duration_ms: 1.0, call_site: call_site_a)
    expect(tracker.triggered_groups.first.sample_sql).to eq "SELECT 1"
  end
end
