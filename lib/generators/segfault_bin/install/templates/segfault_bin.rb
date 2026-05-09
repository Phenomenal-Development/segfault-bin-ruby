# frozen_string_literal: true

SegfaultBin.configure do |c|
  c.dsn                  = ENV["SEGFAULT_BIN_DSN"]
  c.environment          = Rails.env
  c.release              = ENV["RELEASE_SHA"] || ENV["HEROKU_SLUG_COMMIT"]
  c.enabled_environments = %w[production staging]

  # c.max_events_per_minute   = 100
  # c.additional_filter_keys  = []
  # c.include_request_body    = true
  # c.send_default_pii        = false
  # c.async                   = true

  # N+1 query detection (HTTP requests only)
  # c.detect_n_plus_one          = false
  # c.n_plus_one_threshold       = 5
  # c.n_plus_one_min_duration_ms = 0.0
  # c.n_plus_one_max_groups      = 1000
end
