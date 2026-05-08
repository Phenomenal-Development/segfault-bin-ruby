# frozen_string_literal: true

RSpec.describe SegfaultBin::RateLimiter do
  it "allows up to N events per minute" do
    limiter = described_class.new(3)
    expect(limiter.throttled?).to be false
    expect(limiter.throttled?).to be false
    expect(limiter.throttled?).to be false
    expect(limiter.throttled?).to be true
  end

  it "expires entries older than 60 seconds" do
    limiter = described_class.new(2)
    base = Time.now.to_f

    allow(Time).to receive(:now).and_return(Time.at(base))
    expect(limiter.throttled?).to be false
    expect(limiter.throttled?).to be false
    expect(limiter.throttled?).to be true

    allow(Time).to receive(:now).and_return(Time.at(base + 61))
    expect(limiter.throttled?).to be false
  end
end
