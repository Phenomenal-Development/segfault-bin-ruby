# frozen_string_literal: true

require "segfault_bin/version"
require "segfault_bin/configuration"
require "segfault_bin/current_request"
require "segfault_bin/scrubber"
require "segfault_bin/frame_builder"
require "segfault_bin/payload_builder"
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

    def rate_limiter
      @rate_limiter ||= RateLimiter.new(config.max_events_per_minute)
    end

    def reset!
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
      return unless defined?(Rails) && Rails.respond_to?(:error)
      Rails.error.subscribe(Subscriber.new(self))
    end
  end
end
