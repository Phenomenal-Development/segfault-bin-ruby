## [Unreleased]

- Ignore client-triggered 4xx exceptions by default. New `excluded_exceptions`
  config, pre-populated with the Rails/Rack/Puma/Mongoid exceptions that
  represent the framework working as designed (`ActiveRecord::RecordNotFound`,
  `ActionController::RoutingError`, `ActionController::InvalidAuthenticityToken`,
  `ActionController::TooManyRequests`, ...) rather than a server-side defect.
  Matching walks the exception's ancestor chain by name, so subclasses are
  covered and names that aren't loaded in the host app never match. The check
  runs ahead of the rate limiter, so ignored noise no longer eats
  `max_events_per_minute` budget. Append with `c.excluded_exceptions += [...]`
  to keep the defaults.
- Add `benchmark` as a development dependency — it stopped being a default gem
  in Ruby 4.0, which broke `bundle exec rspec` on that version.
- Application log capture and shipping. Opt-in via `config.send_logs = true`;
  the gem attaches itself to `Rails.logger` via `ActiveSupport::BroadcastLogger`
  (Rails 7.1+) and ships log entries to `POST /api/logs` in batches.
- New config options: `send_logs`, `log_min_level` (default `:info`),
  `log_endpoint_path` (default `/api/logs`), `log_batch_size` (50),
  `log_flush_interval` (2.0s), `log_max_buffer` (1000), `log_source` (`"rails"`).
- Server-authoritative disable: when the server returns 204 (project has
  `logs_enabled=false`), the batcher backs off for 60 seconds.
- `SegfaultBin.flush_logs` for graceful shutdown in tests and scripts.

## [0.2.0] - 2026-05-09

- N+1 detection: remove the 30-frame cap on call-site resolution. With Rails view
  rendering on the stack, the user-code frame routinely sat 40+ deep, so events
  were dropped silently in production. The resolver now walks the full caller.
- N+1 detection: capture the preceding query for each repeating group, so the
  parent SELECT is reported alongside the children.
- N+1 detection: collect up to 5 sample SQLs per group (gated on `send_default_pii`).
- Payload: add top-level `transaction` (controller#action), `request_id`,
  `runtime`, and a `contexts` map (`runtime`, `os`, optional `browser`,
  `client_os`, `device` parsed from User-Agent).
- Payload: `request` now also exposes `path`, `host`, `scheme`, `port`, and
  `env.SERVER_NAME` / `env.SERVER_PORT`.
- N+1 events expose `parent_span` per group and `preceding_span` carrying the
  parent fingerprint (sql gated on `send_default_pii`).

## [0.1.0] - 2026-05-08

- Initial release
