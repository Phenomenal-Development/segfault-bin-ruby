#!/usr/bin/env bash
# Smoke test against a locally running Segfault Bin collector.
#
# Usage:
#   ./test.sh                                # uses defaults below
#   SEGFAULT_BIN_DSN=http://tok@localhost:3000/api/events ./test.sh

set -euo pipefail

cd "$(dirname "$0")"

: "${SEGFAULT_BIN_DSN:=http://e3793c542f8b301b0d053b669899c4afd7312abf5f820020556b8c17d6c17408@localhost:3000/api/events}"
export SEGFAULT_BIN_DSN

echo "Reporting test exception to: ${SEGFAULT_BIN_DSN}"

bundle exec ruby -Ilib -rsegfault_bin -e '
  SegfaultBin.configure do |c|
    c.dsn         = ENV["SEGFAULT_BIN_DSN"]
    c.environment = "production"
    c.release     = "test-release"
    c.async       = false
  end

  begin
    raise "hello from segfault_bin test.sh at #{Time.now}"
  rescue => e
    SegfaultBin.report(e, context: {
      user:  { id: 1, email: "test@example.com" },
      extra: { source: "test.sh" },
      tags:  { smoke: "true" }
    })
  end

  puts "Reported. Check the collector."
'
