# frozen_string_literal: true

SegfaultBin.configure do |c|
  c.dsn                  = ENV["SEGFAULT_BIN_DSN"]
  c.environment          = Rails.env
  c.release              = ENV["RELEASE_SHA"] || ENV["HEROKU_SLUG_COMMIT"]
  c.enabled_environments = %w[production staging]

  # c.max_events_per_minute   = 100
  # c.additional_filter_keys  = []

  # Client-triggered 4xx exceptions are ignored by default: RecordNotFound,
  # RoutingError, InvalidAuthenticityToken, ParameterMissing and friends. The
  # full list is SegfaultBin::Configuration::DEFAULT_EXCLUDED_EXCEPTIONS.
  #
  # Append your own with `+=` rather than assigning, so you keep the defaults.
  # Subclasses of anything listed are ignored too:
  # c.excluded_exceptions += %w[Billing::CardDeclined Api::InvalidSignature]
  #
  # Start reporting one of the defaults again:
  # c.excluded_exceptions -= %w[ActiveRecord::RecordNotFound]
  #
  # Report everything, no exclusions at all:
  # c.excluded_exceptions = []
  #
  # Names are strings on purpose — referencing your own error classes as
  # constants here would autoload app code during initialization.

  # c.include_request_body    = true
  # c.send_default_pii        = false
  # c.async                   = true

  # N+1 query detection (HTTP requests only)
  # c.detect_n_plus_one          = false
  # c.n_plus_one_threshold       = 5
  # c.n_plus_one_min_duration_ms = 0.0
  # c.n_plus_one_max_groups      = 1000
end
