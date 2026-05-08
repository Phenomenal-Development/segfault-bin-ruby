# frozen_string_literal: true

require "rails/railtie"
require_relative "middleware/capture_request"

module SegfaultBin
  class Railtie < Rails::Railtie
    initializer "segfault_bin.middleware" do |app|
      app.middleware.use SegfaultBin::Middleware::CaptureRequest
    end

    config.after_initialize do
      if SegfaultBin.config.dsn.to_s.empty? &&
          SegfaultBin.config.enabled_environments.include?(Rails.env)
        Rails.logger&.warn("[SegfaultBin] DSN not configured, error reporting disabled")
      end
    end
  end
end
