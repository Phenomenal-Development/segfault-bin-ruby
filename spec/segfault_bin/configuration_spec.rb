# frozen_string_literal: true

RSpec.describe SegfaultBin::Configuration do
  subject(:config) { described_class.new }

  describe "#enabled?" do
    it "is false when dsn is missing" do
      config.environment = "production"
      expect(config.enabled?).to be false
    end

    it "is false in non-enabled environments" do
      config.dsn = "https://t@example.com/api/events"
      config.environment = "development"
      expect(config.enabled?).to be false
    end

    it "is true with dsn in an enabled environment" do
      config.dsn = "https://t@example.com/api/events"
      config.environment = "production"
      expect(config.enabled?).to be true
    end
  end

  describe "#validate!" do
    it "raises when dsn missing in enabled environment" do
      config.environment = "production"
      expect { config.validate! }.to raise_error(ArgumentError, /dsn must be set/)
    end

    it "does not raise when dsn missing in disabled environment" do
      config.environment = "development"
      expect { config.validate! }.not_to raise_error
    end
  end

  describe "#auth_token" do
    it "extracts the userinfo token from the DSN" do
      config.dsn = "https://abc123@bin.example.com/api/events"
      expect(config.auth_token).to eq "abc123"
    end
  end

  describe "defaults" do
    it "has a 100/min rate limit" do
      expect(config.max_events_per_minute).to eq 100
    end

    it "defaults send_default_pii to false" do
      expect(config.send_default_pii).to be false
    end

    it "enables production and staging by default" do
      expect(config.enabled_environments).to contain_exactly("production", "staging")
    end
  end
end
