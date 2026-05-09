# frozen_string_literal: true

RSpec.describe SegfaultBin::NPlusOne::Subscriber do
  let(:call_site) { {abs_path: "/app/x.rb", filename: "x.rb", lineno: 1, function: "f", in_app: true} }
  let(:resolver) { instance_double(SegfaultBin::NPlusOne::CallSiteResolver, resolve: call_site) }
  let(:tracker) { SegfaultBin::NPlusOne::Tracker.new(threshold: 3) }

  before do
    SegfaultBin::CurrentRequest.n_plus_one_tracker = tracker
  end

  def handle(payload, duration_ms: 1.0)
    start = 0.0
    finish = start + duration_ms / 1000.0
    described_class.handle(start, finish, payload, resolver, 0.0)
  end

  it "skips cached queries" do
    handle({sql: "SELECT 1", cached: true})
    expect(tracker.triggered_groups).to be_empty
  end

  it "skips SCHEMA queries" do
    handle({sql: "SELECT 1", name: "SCHEMA"})
    expect(tracker.triggered_groups).to be_empty
  end

  it "is a no-op when no tracker is set" do
    SegfaultBin::CurrentRequest.n_plus_one_tracker = nil
    expect { handle({sql: "SELECT 1"}) }.not_to raise_error
  end

  it "does nothing when sql is nil" do
    handle({})
    expect(tracker.triggered_groups).to be_empty
  end

  it "drops events when call site cannot be resolved but still records preceding context" do
    allow(resolver).to receive(:resolve).and_return(nil)
    handle({sql: "SELECT * FROM customers ORDER BY last_name"})
    expect(tracker.triggered_groups).to be_empty
    # Now that a real call site resolves, the next burst should pick up the prior SQL as preceding.
    allow(resolver).to receive(:resolve).and_return(call_site)
    3.times { handle({sql: "SELECT COUNT(*) FROM orders WHERE customer_id = 1"}) }
    g = tracker.triggered_groups.first
    expect(g.preceding_query.fingerprint).to include("customers")
  end

  it "records and triggers at threshold" do
    3.times { handle({sql: "SELECT * FROM users WHERE id = 1"}) }
    expect(tracker.triggered_groups.size).to eq 1
    expect(tracker.triggered_groups.first.count).to eq 3
  end

  it "skips queries below min_duration_ms" do
    described_class.handle(0.0, 0.0001, {sql: "SELECT 1"}, resolver, 1.0)
    expect(tracker.triggered_groups).to be_empty
  end
end
