# frozen_string_literal: true

require "segfault_bin/version"
require "segfault_bin/configuration"
require "segfault_bin/current_request"
require "segfault_bin/scrubber"
require "segfault_bin/frame_builder"
require "segfault_bin/request_context"
require "segfault_bin/payload_builder"
require "segfault_bin/n_plus_one/fingerprinter"
require "segfault_bin/n_plus_one/call_site_resolver"
require "segfault_bin/n_plus_one/tracker"
require "segfault_bin/n_plus_one/subscriber"
require "segfault_bin/n_plus_one_payload_builder"
require "segfault_bin/transport"
require "segfault_bin/rate_limiter"
require "segfault_bin/subscriber"
require "segfault_bin/middleware/capture_request"
require "segfault_bin/railtie" if defined?(Rails::Railtie)

module SegfaultBin
  class Error < StandardError; end

  class << self
    def configure
      yield(config)
      config.validate!
      install! if config.enabled?
    end

    def config
      @config ||= Configuration.new
    end

    def transport
      @transport ||= Transport.build(config)
    end

    def report(exception, context: {})
      return unless config.enabled?
      return if rate_limiter.throttled?
      payload = PayloadBuilder.new(exception, context, config).build
      transport.deliver(payload)
    rescue => e
      config.logger.error("[SegfaultBin] failed to report: #{e.class} #{e.message}")
    end

    def report_n_plus_one(triggered_groups, truncated:)
      return unless config.enabled?
      return if triggered_groups.nil? || triggered_groups.empty?
      return if rate_limiter.throttled?
      payload = NPlusOnePayloadBuilder.new(triggered_groups, truncated, config).build
      transport.deliver(payload)
    rescue => e
      config.logger.error("[SegfaultBin] failed to report n+1: #{e.class} #{e.message}")
    end

    def rate_limiter
      @rate_limiter ||= RateLimiter.new(config.max_events_per_minute)
    end

    def reset!
      NPlusOne::Subscriber.detach!
      @transport.shutdown if @transport.respond_to?(:shutdown)
      @config = nil
      @transport = nil
      @rate_limiter = nil
    end

    def reset_transport!
      @transport.shutdown if @transport.respond_to?(:shutdown)
      @transport = nil
    end

    private

    def install!
      if defined?(Rails) && Rails.respond_to?(:error)
        Rails.error.subscribe(Subscriber.new(self))
        config.logger.info("[SegfaultBin] subscribed to Rails.error (env=#{config.environment}, dsn_host=#{safe_dsn_host})")
      end
      if config.detect_n_plus_one
        NPlusOne::Subscriber.attach!(config)
        config.logger.info("[SegfaultBin] N+1 detection enabled (threshold=#{config.n_plus_one_threshold})")
      end
    end

    def safe_dsn_host
      config.endpoint.host
    rescue
      "<unparseable>"
    end
  end
end
