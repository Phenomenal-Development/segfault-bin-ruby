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
end
