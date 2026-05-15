# SegfaultBin

Self-hosted error reporter for Rails. Companion to the Segfault Bin collector.

Captures unhandled exceptions, builds rich payloads with stack traces and
request context, and ships them to a Segfault Bin collector.

## Installation

```ruby
# Gemfile
gem "segfault_bin"
```

Then generate the initializer:

```sh
bin/rails g segfault_bin:install
```

This creates `config/initializers/segfault_bin.rb` with sensible defaults:

```ruby
SegfaultBin.configure do |c|
  c.dsn                  = ENV["SEGFAULT_BIN_DSN"]
  c.environment          = Rails.env
  c.release              = ENV["RELEASE_SHA"] || ENV["HEROKU_SLUG_COMMIT"]
  c.enabled_environments = %w[production staging]
end
```

Set `SEGFAULT_BIN_DSN` in your environment. The DSN format: `https://<token>@host/api/events`.

## Usage

Unhandled exceptions in Rails (controllers, ActiveJob, Solid Queue) are
captured automatically via `Rails.error.subscribe`.

To attach user context to the current request (e.g. in a `before_action`):

```ruby
SegfaultBin::CurrentRequest.set_user(id: current_user.id, email: current_user.email)
```

To report manually:

```ruby
SegfaultBin.report(exception, context: { user: { id: 1 }, extra: { foo: "bar" } })
```

## Production setup

Delivery runs on a background thread by default (`config.async = true`), so
reporting never blocks the request thread. Two things are required for this
to work safely under a forking server like Puma:

**1. Reset the transport after fork.** The background worker thread does not
survive a fork. In `config/puma.rb`:

```ruby
on_worker_boot do
  SegfaultBin.reset_transport!
end
```

The next call to `SegfaultBin.report` in the worker process will lazily build
a fresh transport with its own worker thread.

**2. Build payloads on the request thread.** `SegfaultBin.report` builds the
payload synchronously (which captures `CurrentRequest`, thread-local state,
etc.) and only hands the finished payload to the worker thread for delivery.
Do not move payload construction onto a background thread of your own.

If the collector is unreachable, deliveries retry up to 3 times with
exponential backoff. `429 Retry-After` is honored. If the in-memory queue
fills up (default `100` events), further events are dropped and a periodic
warning is logged — the request thread is never blocked.

## Configuration

| Option | Default | Notes |
|---|---|---|
| `dsn` | — | Required in enabled environments |
| `enabled_environments` | `%w[production staging]` | |
| `max_events_per_minute` | `100` | Per-process sliding window |
| `additional_filter_keys` | `[]` | Merged with `Rails.application.config.filter_parameters` |
| `include_request_body` | `true` | |
| `include_frame_vars` | `false` | Reserved for future use |
| `app_dirs_pattern` | `Rails.root` | Path prefix used to mark frames as `in_app` |
| `send_default_pii` | `false` | When true, attaches `request.remote_ip` to the user payload, and includes `sample_sql` in N+1 events |
| `async` | `true` | When true, delivery runs on a background worker thread (see Production setup) |
| `detect_n_plus_one` | `false` | Opt-in N+1 SQL query detection (HTTP requests only) |
| `n_plus_one_threshold` | `5` | Occurrences of the same query group needed to fire an event |
| `n_plus_one_min_duration_ms` | `0.0` | Minimum query duration to count |
| `n_plus_one_max_groups` | `1000` | Per-request memory cap on tracked groups |

## N+1 query detection

When `detect_n_plus_one = true`, SegfaultBin subscribes to the
`sql.active_record` notification and tracks queries per HTTP request,
grouping by normalized SQL fingerprint and the first in-app caller. When
the same group repeats `n_plus_one_threshold` times within one request,
an `n_plus_one_query` event is emitted to the collector.

The detection adds minimal overhead per query: cached and schema queries
are skipped immediately, and group state is bounded by
`n_plus_one_max_groups`. The fingerprint is always sent; the raw
`sample_sql`, the per-group `samples` (up to 5), and the `preceding_span`'s
literal SQL are only included when `send_default_pii = true`, since literal
values may contain PII.

Each event also carries the parent SELECT that immediately preceded the
burst (`groups[].preceding_span`), the matching controller action
(`transaction`, `groups[].parent_span`), the Rails `request_id`, and a
`contexts` map (`runtime`, `os`, plus `browser`/`client_os`/`device` parsed
from the User-Agent when present).

Known v1 limitations:

- HTTP requests only — ActiveJob is not yet covered.
- Background threads spawned mid-request will not be tracked
  (`CurrentAttributes` is per-thread).
- N+1 events share the `max_events_per_minute` budget with exception events.

## Capturing application logs

SegfaultBin can also ship application logs (anything written to `Rails.logger`)
to the collector, alongside exceptions and N+1 events. Logs are captured by
attaching to `Rails.logger` via `ActiveSupport::BroadcastLogger` (requires Rails 7.1+),
batched in a background thread, and POSTed to `/api/logs`.

Enable it in your initializer:

```ruby
SegfaultBin.configure do |c|
  c.dsn       = ENV["SEGFAULT_BIN_DSN"]
  c.send_logs = true
  c.log_min_level = :info   # :debug, :info, :warn, :error, :fatal
end
```

The collector also has a per-project toggle — when the project's "logs enabled"
setting is off, the server returns 204 and the gem backs off for 60 seconds
before trying again, so it's safe to leave `send_logs = true` in the gem and
control rollout from the collector.

### Log config options

| Option | Default | Notes |
|---|---|---|
| `send_logs` | `false` | Master switch on the gem side |
| `log_min_level` | `:info` | Minimum severity to ship (`:debug` / `:info` / `:warn` / `:error` / `:fatal`) |
| `log_endpoint_path` | `"/api/logs"` | Path used relative to the DSN host |
| `log_batch_size` | `50` | Flush threshold |
| `log_flush_interval` | `2.0` | Seconds — flush even when below batch size |
| `log_max_buffer` | `1000` | Buffer cap; oldest entries are dropped on overflow |
| `log_source` | `"rails"` | String tag attached to each entry (`source` column on the collector) |

Each log entry carries the configured `environment`, `release`, `server_name`,
the current `request_id` (from `action_dispatch.request_id` or `X-Request-Id`),
and a free-form `source` tag.

Use `SegfaultBin.flush_logs` to drain the buffer in tests or just before a
graceful shutdown.

## Development

```sh
bin/setup
bundle exec rspec
gem build segfault_bin.gemspec
```

## License

MIT.
