# frozen_string_literal: true

RSpec.describe SegfaultBin::Scrubber do
  let(:config) do
    SegfaultBin::Configuration.new.tap do |c|
      c.additional_filter_keys = [:secret_handshake]
    end
  end

  it "redacts default sensitive keys at any depth" do
    payload = {
      user: {email: "a@b.com", password: "hunter2"},
      request: {params: {api_key: "sk-xxx", username: "alice"}}
    }
    out = described_class.call(payload, config: config)

    expect(out[:user][:password]).to eq "[FILTERED]"
    expect(out[:request][:params][:api_key]).to eq "[FILTERED]"
    expect(out[:user][:email]).to eq "a@b.com"
    expect(out[:request][:params][:username]).to eq "alice"
  end

  it "redacts additional_filter_keys" do
    payload = {extra: {secret_handshake: "shake"}}
    out = described_class.call(payload, config: config)
    expect(out[:extra][:secret_handshake]).to eq "[FILTERED]"
  end

  it "walks arrays" do
    payload = {entries: [{token: "t1"}, {token: "t2"}]}
    out = described_class.call(payload, config: config)
    expect(out[:entries].map { |e| e[:token] }).to eq %w[[FILTERED] [FILTERED]]
  end
end
