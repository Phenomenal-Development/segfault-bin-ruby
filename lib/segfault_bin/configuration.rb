# frozen_string_literal: true

require "logger"
require "socket"
require "uri"

module SegfaultBin
  class Configuration
    LOG_LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4, unknown: 5 }.freeze

    # Exceptions that are client-triggered 4xx responses: the framework working
    # as designed, not server-side defects anyone can fix. The trigger is
    # external input — stale links, bots probing sequential IDs, tampered URLs,
    # a CSRF check doing its job — so reporting them only buries real errors.
    #
    # Mirrors sentry-ruby's IGNORE_DEFAULT + PUMA_IGNORE_DEFAULT, sentry-rails'
    # IGNORE_DEFAULT, and RAILS_8_1_1_IGNORE_DEFAULT. Kept verbatim so the list
    # is auditable against Sentry's; entries whose constant is not defined in a
    # given app (Mongoid, Sinatra, Rails < 8.1.1) simply never match.
    DEFAULT_EXCLUDED_EXCEPTIONS = %w[
      AbstractController::ActionNotFound
      ActionController::BadRequest
      ActionController::InvalidAuthenticityToken
      ActionController::InvalidCrossOriginRequest
      ActionController::MethodNotAllowed
      ActionController::NotImplemented
      ActionController::ParameterMissing
      ActionController::RoutingError
      ActionController::TooManyRequests
      ActionController::UnknownAction
      ActionController::UnknownFormat
      ActionController::UnknownHttpMethod
      ActionDispatch::Http::MimeNegotiation::InvalidType
      ActionDispatch::Http::Parameters::ParseError
      ActiveRecord::RecordNotFound
      Mongoid::Errors::DocumentNotFound
      Puma::HttpParserError
      Puma::HttpParserError501
      Puma::MiniSSL::SSLError
      Rack::QueryParser::InvalidParameterError
      Rack::QueryParser::ParameterTypeError
      Sinatra::NotFound
    ].freeze

    attr_accessor :dsn, :environment, :release, :server_name,
      :enabled_environments, :max_events_per_minute,
      :excluded_exceptions,
      :additional_filter_keys, :include_request_body,
      :include_frame_vars, :app_dirs_pattern, :logger, :async,
      :send_default_pii,
      :detect_n_plus_one, :n_plus_one_threshold,
      :n_plus_one_min_duration_ms, :n_plus_one_max_groups,
      :detect_slow_queries, :slow_query_min_duration_ms,
      :slow_query_min_allocations, :slow_query_max_groups,
      :send_logs, :log_endpoint_path,
      :log_batch_size, :log_flush_interval, :log_max_buffer,
      :log_source

    attr_reader :log_min_level

    def initialize
      @enabled_environments = %w[production staging]
      @max_events_per_minute = 100
      @excluded_exceptions = DEFAULT_EXCLUDED_EXCEPTIONS.dup
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
      @detect_slow_queries = false
      @slow_query_min_duration_ms = 100.0
      @slow_query_min_allocations = 10_000
      @slow_query_max_groups = 200
      @environment = ENV["RAILS_ENV"] || "development"
      @release = ENV["RELEASE_SHA"] || ENV["HEROKU_SLUG_COMMIT"]
      @server_name = ENV["DYNO"] || Socket.gethostname
      @logger = Logger.new($stderr)
      @send_logs = false
      self.log_min_level = :info
      @log_endpoint_path = "/api/logs"
      @log_batch_size = 50
      @log_flush_interval = 2.0
      @log_max_buffer = 1000
      @log_source = "rails"
    end

    def log_min_level=(value)
      level = value.is_a?(Symbol) ? value : value.to_s.downcase.to_sym
      raise ArgumentError, "unknown log level #{value.inspect}" unless LOG_LEVELS.key?(level)
      @log_min_level = level
    end

    def log_min_severity
      LOG_LEVELS.fetch(@log_min_level)
    end

    def enabled?
      !dsn.to_s.empty? && enabled_environments.include?(environment)
    end

    # Entries may be Strings or Class/Module objects; both normalize to a name.
    def excluded_exception_names
      Array(excluded_exceptions).map { |e| e.is_a?(Module) ? e.name : e.to_s }.compact
    end

    # Matched against the whole ancestor chain by name rather than by constant,
    # so a subclass of an ignored exception is ignored too and a name that is
    # not loaded in this app never raises.
    def excluded_exception?(exception)
      names = excluded_exception_names
      return false if names.empty?
      exception.class.ancestors.any? { |ancestor| names.include?(ancestor.name) }
    end

    def logs_enabled?
      enabled? && @send_logs
    end

    def endpoint
      URI.parse(dsn)
    end

    def auth_token
      endpoint.user || endpoint.path.split("/").last
    end

    # Safe-to-expose snapshot of the gem's runtime configuration. Embedded in
    # each event envelope under `sdk[:config]` so the collector can show users
    # what their app is currently reporting with. Excludes `dsn` and the raw
    # filter key list (potentially sensitive).
    def snapshot
      {
        enabled: enabled?,
        enabled_environments: enabled_environments,
        async: async,
        send_default_pii: send_default_pii,
        include_request_body: include_request_body,
        include_frame_vars: include_frame_vars,
        max_events_per_minute: max_events_per_minute,
        excluded_exceptions: excluded_exception_names,
        additional_filter_key_count: additional_filter_keys.length,
        detect_n_plus_one: detect_n_plus_one,
        n_plus_one_threshold: n_plus_one_threshold,
        n_plus_one_min_duration_ms: n_plus_one_min_duration_ms,
        n_plus_one_max_groups: n_plus_one_max_groups,
        detect_slow_queries: detect_slow_queries,
        slow_query_min_duration_ms: slow_query_min_duration_ms,
        slow_query_min_allocations: slow_query_min_allocations,
        slow_query_max_groups: slow_query_max_groups,
        send_logs: send_logs,
        log_min_level: log_min_level,
        log_batch_size: log_batch_size,
        log_flush_interval: log_flush_interval,
        log_max_buffer: log_max_buffer,
        log_source: log_source
      }
    end
  end
end
