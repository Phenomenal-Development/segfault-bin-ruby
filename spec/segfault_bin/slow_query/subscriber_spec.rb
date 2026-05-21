# frozen_string_literal: true

RSpec.describe SegfaultBin::SlowQuery::Subscriber do
  let(:call_site) { {abs_path: "/app/x.rb", filename: "x.rb", lineno: 1, function: "f", in_app: true} }
  let(:resolver) { instance_double(SegfaultBin::NPlusOne::CallSiteResolver, resolve: call_site) }
  let(:tracker) { SegfaultBin::SlowQuery::Tracker.new }

  before do
    SegfaultBin::CurrentRequest.slow_query_tracker = tracker
  end

  def handle(payload, duration_ms: 200.0, allocations: 0, min_ms: 100.0, min_alloc: 10_000)
    event = instance_double(
      "ActiveSupport::Notifications::Event",
      payload: payload,
      duration: duration_ms,
      allocations: allocations
    )
    allow(event).to receive(:respond_to?).with(:allocations).and_return(true)
    described_class.handle(event, resolver, min_ms, min_alloc)
  end

  it "skips cached queries" do
    handle({sql: "SELECT 1", cached: true})
    expect(tracker.groups).to be_empty
  end

  it "skips SCHEMA queries" do
    handle({sql: "SELECT 1", name: "SCHEMA"})
    expect(tracker.groups).to be_empty
  end

  it "skips queries below both thresholds" do
    handle({sql: "SELECT 1"}, duration_ms: 5.0, allocations: 10)
    expect(tracker.groups).to be_empty
  end

  it "records when duration alone breaches" do
    handle({sql: "SELECT 1"}, duration_ms: 150.0, allocations: 100)
    g = tracker.groups.first
    expect(g.kinds.to_a).to eq([:slow_duration])
  end

  it "records when allocations alone breach" do
    handle({sql: "SELECT 1"}, duration_ms: 5.0, allocations: 20_000)
    g = tracker.groups.first
    expect(g.kinds.to_a).to eq([:high_allocations])
  end

  it "records with both kinds when both breach" do
    handle({sql: "SELECT 1"}, duration_ms: 150.0, allocations: 20_000)
    expect(tracker.groups.first.kinds.to_a).to contain_exactly(:slow_duration, :high_allocations)
  end

  it "is a no-op when no tracker is set" do
    SegfaultBin::CurrentRequest.slow_query_tracker = nil
    expect {
      handle({sql: "SELECT 1"}, duration_ms: 500.0)
    }.not_to raise_error
  end

  it "does nothing when sql is nil" do
    handle({}, duration_ms: 500.0)
    expect(tracker.groups).to be_empty
  end

  it "skips when call site cannot be resolved" do
    allow(resolver).to receive(:resolve).and_return(nil)
    handle({sql: "SELECT 1"}, duration_ms: 500.0)
    expect(tracker.groups).to be_empty
  end

  it "stops recording once tracker is full" do
    full_tracker = SegfaultBin::SlowQuery::Tracker.new(max_groups: 1)
    SegfaultBin::CurrentRequest.slow_query_tracker = full_tracker
    handle({sql: "SELECT * FROM users"}, duration_ms: 150.0)
    handle({sql: "SELECT * FROM posts"}, duration_ms: 150.0)
    expect(full_tracker.full?).to be true
    expect {
      handle({sql: "SELECT * FROM comments"}, duration_ms: 150.0)
    }.not_to(change { full_tracker.groups.size })
  end
end
