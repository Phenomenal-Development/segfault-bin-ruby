## [Unreleased]

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
