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
| `send_default_pii` | `false` | When true, attaches `request.remote_ip` to the user payload |
| `async` | `true` | When true, delivery runs on a background worker thread (see Production setup) |

## Development

```sh
bin/setup
bundle exec rspec
gem build segfault_bin.gemspec
```

## License

MIT.
