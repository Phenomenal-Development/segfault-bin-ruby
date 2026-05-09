# frozen_string_literal: true

require "logger"
require "socket"
require "uri"

module SegfaultBin
  class Configuration
    attr_accessor :dsn, :environment, :release, :server_name,
      :enabled_environments, :max_events_per_minute,
      :additional_filter_keys, :include_request_body,
      :include_frame_vars, :app_dirs_pattern, :logger, :async,
      :send_default_pii,
      :detect_n_plus_one, :n_plus_one_threshold,
      :n_plus_one_min_duration_ms, :n_plus_one_max_groups

    def initialize
      @enabled_environments = %w[production staging]
      @max_events_per_minute = 100
      @additional_filter_keys = []
      @include_request_body = true
      @include_frame_vars = false
      @app_dirs_pattern = nil
      @async = true
      @send_default_pii = false
      @detect_n_plus_one = false
      @n_plus_one_threshold = 5
      @n_plus_one_min_duration_ms = 0.0
      @n_plus_one_max_groups = 1000
      @environment = ENV["RAILS_ENV"] || "development"
      @release = ENV["RELEASE_SHA"] || ENV["HEROKU_SLUG_COMMIT"]
      @server_name = ENV["DYNO"] || Socket.gethostname
      @logger = Logger.new($stderr)
    end

    def enabled?
      !dsn.to_s.empty? && enabled_environments.include?(environment)
    end

    def validate!
      if dsn.to_s.empty? && enabled_environments.include?(environment)
        raise ArgumentError, "SegfaultBin.config.dsn must be set"
      end
    end

    def endpoint
      URI.parse(dsn)
    end

    def auth_token
      endpoint.user || endpoint.path.split("/").last
    end
  end
end
