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

  it "captures the preceding query as the parent of a group" do
    tracker = described_class.new(threshold: 2)
    tracker.note_query(fingerprint: "select * from customers", sql: "SELECT * FROM customers ORDER BY last_name", duration_ms: 4.2)
    2.times { tracker.record(fingerprint: "count(*) orders", sql: "SELECT COUNT(*) FROM orders", duration_ms: 0.5, call_site: call_site_a) }
    g = tracker.triggered_groups.first
    expect(g.preceding_query).not_to be_nil
    expect(g.preceding_query.fingerprint).to eq "select * from customers"
    expect(g.preceding_query.sql).to include("ORDER BY")
  end

  it "accumulates samples up to the cap" do
    tracker = described_class.new(threshold: 2)
    8.times do |i|
      tracker.record(fingerprint: "f", sql: "SELECT #{i}", duration_ms: 1.0, call_site: call_site_a)
    end
    samples = tracker.triggered_groups.first.samples
    expect(samples.size).to eq SegfaultBin::NPlusOne::Tracker::MAX_SAMPLES_PER_GROUP
    expect(samples.first.sql).to eq "SELECT 0"
  end

  it "still tracks the last query when the group cap is hit" do
    tracker = described_class.new(threshold: 1, max_groups: 1)
    tracker.record(fingerprint: "a", sql: "A", duration_ms: 1.0, call_site: call_site_a)
    tracker.record(fingerprint: "b", sql: "B", duration_ms: 1.0, call_site: call_site_a)
    expect(tracker.full?).to be true
    # next group records its preceding from this point — record won't add the group
    tracker.note_query(fingerprint: "c", sql: "C", duration_ms: 1.0)
    expect { tracker.record(fingerprint: "d", sql: "D", duration_ms: 1.0, call_site: call_site_a) }.not_to raise_error
  end
end
