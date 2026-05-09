# frozen_string_literal: true

require "time"
require_relative "request_context"
require_relative "scrubber"

module SegfaultBin
  class NPlusOnePayloadBuilder
    EVENT_TYPE = "n_plus_one_query"
    LEVEL = "warning"

    def initialize(triggered_groups, truncated, config)
      @groups = triggered_groups
      @truncated = truncated
      @config = config
    end

    def build
      payload = RequestContext.envelope(@config, level: LEVEL, type: EVENT_TYPE)
      payload.merge!(
        request: RequestContext.request_data(@config),
        user: RequestContext.user_data(@config),
        tags: {source: "n_plus_one"},
        groups: @groups.map { |g| serialize_group(g) },
        groups_truncated: @truncated
      )
      Scrubber.call(payload, config: @config)
    end

    private

    def serialize_group(group)
      data = {
        fingerprint: group.fingerprint,
        call_site: group.call_site,
        count: group.count,
        total_duration_ms: group.total_duration_ms.round(3),
        first_seen_at: format_time(group.first_seen_at),
        last_seen_at: format_time(group.last_seen_at)
      }
      data[:sample_sql] = group.sample_sql if @config.send_default_pii
      data
    end

    def format_time(t)
      t.respond_to?(:utc) ? t.utc.iso8601(3) : t.to_s
    end
  end
end
