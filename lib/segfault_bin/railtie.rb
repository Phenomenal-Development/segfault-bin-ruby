# frozen_string_literal: true

require "rails/railtie"
require_relative "middleware/capture_request"

module SegfaultBin
  class Railtie < Rails::Railtie
    initializer "segfault_bin.middleware" do |app|
      app.middleware.use SegfaultBin::Middleware::CaptureRequest
    end

    initializer "segfault_bin.log_capture", after: :initialize_logger do |_app|
      cfg = SegfaultBin.config
      next unless cfg.logs_enabled?

      sink = SegfaultBin.log_sink
      next unless sink

      if defined?(ActiveSupport::BroadcastLogger)
        if Rails.logger.is_a?(ActiveSupport::BroadcastLogger)
          unless Rails.logger.broadcasts.include?(sink)
            Rails.logger.broadcast_to(sink)
          end
        else
          Rails.logger = ActiveSupport::BroadcastLogger.new(Rails.logger, sink)
        end
        cfg.logger&.info("[SegfaultBin] log capture attached to Rails.logger (min_level=#{cfg.log_min_level})")
      else
        cfg.logger&.warn("[SegfaultBin] ActiveSupport::BroadcastLogger not available; log capture disabled (requires Rails 7.1+)")
      end
    end

    config.after_initialize do
      cfg = SegfaultBin.config
      if cfg.dsn.to_s.empty? && cfg.enabled_environments.include?(Rails.env)
        Rails.logger&.warn("[SegfaultBin] DSN not configured, error reporting disabled")
      elsif !cfg.dsn.to_s.empty? && !cfg.enabled_environments.include?(cfg.environment)
        Rails.logger&.warn(
          "[SegfaultBin] DSN is set but environment #{cfg.environment.inspect} is not in " \
          "enabled_environments #{cfg.enabled_environments.inspect}; error reporting disabled. " \
          "Add #{cfg.environment.inspect} to config.enabled_environments to enable."
        )
      end
    end
  end
end
