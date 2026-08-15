# frozen_string_literal: true

require "action_controller"

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

    it "disables N+1 detection by default" do
      expect(config.detect_n_plus_one).to be false
    end

    it "uses N+1 threshold of 5 by default" do
      expect(config.n_plus_one_threshold).to eq 5
    end

    it "uses N+1 max_groups of 1000 by default" do
      expect(config.n_plus_one_max_groups).to eq 1000
    end

    it "uses N+1 min_duration_ms of 0.0 by default" do
      expect(config.n_plus_one_min_duration_ms).to eq 0.0
    end

    it "disables slow query detection by default" do
      expect(config.detect_slow_queries).to be false
    end

    it "uses slow_query_min_duration_ms of 100ms by default" do
      expect(config.slow_query_min_duration_ms).to eq 100.0
    end

    it "uses slow_query_min_allocations of 10_000 by default" do
      expect(config.slow_query_min_allocations).to eq 10_000
    end

    it "uses slow_query_max_groups of 200 by default" do
      expect(config.slow_query_max_groups).to eq 200
    end

    it "excludes the client-triggered 4xx exceptions by default" do
      expect(config.excluded_exceptions).to include(
        "ActiveRecord::RecordNotFound",
        "ActionController::InvalidAuthenticityToken",
        "ActionController::RoutingError",
        "ActionController::TooManyRequests",
        "Rack::QueryParser::ParameterTypeError",
        "Puma::HttpParserError"
      )
    end

    it "does not share the default list between instances" do
      config.excluded_exceptions << "MyApp::Whatever"
      expect(described_class::DEFAULT_EXCLUDED_EXCEPTIONS).not_to include("MyApp::Whatever")
      expect(described_class.new.excluded_exceptions).not_to include("MyApp::Whatever")
    end
  end

  describe "#excluded_exception?" do
    it "matches an exception listed by name" do
      expect(config.excluded_exception?(ActionController::RoutingError.new("no route"))).to be true
    end

    it "matches a subclass of a listed exception" do
      subclass = Class.new(ActionController::RoutingError)
      expect(config.excluded_exception?(subclass.new("no route"))).to be true
    end

    it "does not match an unlisted exception" do
      expect(config.excluded_exception?(StandardError.new("boom"))).to be false
    end

    it "ignores names whose constant is not loaded in this app" do
      config.excluded_exceptions = ["Mongoid::Errors::DocumentNotFound"]
      expect(defined?(Mongoid)).to be_nil
      expect(config.excluded_exception?(StandardError.new("boom"))).to be false
    end

    it "accepts Class entries alongside String ones" do
      config.excluded_exceptions = [ArgumentError, "TypeError"]
      expect(config.excluded_exception?(ArgumentError.new)).to be true
      expect(config.excluded_exception?(TypeError.new)).to be true
      expect(config.excluded_exception?(StandardError.new)).to be false
    end

    it "matches nothing when the list is emptied" do
      config.excluded_exceptions = []
      expect(config.excluded_exception?(ActionController::RoutingError.new("no route"))).to be false
    end

    it "handles an anonymous exception class without matching on its nil name" do
      anon = Class.new(RuntimeError)
      expect(anon.name).to be_nil
      expect(config.excluded_exception?(anon.new)).to be false
    end
  end

  describe "#snapshot" do
    it "exposes feature flags and thresholds for the collector" do
      snap = config.snapshot
      expect(snap).to include(
        :detect_n_plus_one,
        :n_plus_one_threshold,
        :detect_slow_queries,
        :slow_query_min_duration_ms,
        :slow_query_min_allocations,
        :send_default_pii,
        :send_logs,
        :log_min_level
      )
    end

    it "never includes the dsn or raw filter keys" do
      config.dsn = "https://secrettoken@bin.example.com/api/events"
      config.additional_filter_keys = %w[ssn ccnumber]
      snap = config.snapshot
      expect(snap.values).not_to include("secrettoken", "ssn", "ccnumber")
      expect(snap[:additional_filter_key_count]).to eq 2
      expect(snap).not_to have_key(:dsn)
      expect(snap).not_to have_key(:additional_filter_keys)
    end
  end
end
