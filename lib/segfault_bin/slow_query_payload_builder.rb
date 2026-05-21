# frozen_string_literal: true

require "time"
require_relative "request_context"
require_relative "scrubber"

module SegfaultBin
  class SlowQueryPayloadBuilder
    EVENT_TYPE = "slow_query"
    LEVEL = "warning"

    def initialize(groups, truncated, config)
      @groups = groups
      @truncated = truncated
      @config = config
    end

    def build
      payload = RequestContext.envelope(@config, level: LEVEL, type: EVENT_TYPE)
      payload.merge!(
        request: RequestContext.request_data(@config),
        user: RequestContext.user_data(@config),
        tags: {source: "slow_query"},
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
        kinds: group.kinds.to_a.map(&:to_s),
        count: group.count,
        total_duration_ms: group.total_duration_ms.round(3),
        max_duration_ms: group.max_duration_ms.round(3),
        total_allocations: group.total_allocations,
        max_allocations: group.max_allocations,
        first_seen_at: format_time(group.first_seen_at),
        last_seen_at: format_time(group.last_seen_at),
        parent_span: parent_span_label
      }
      if @config.send_default_pii
        data[:sample_sql] = group.sample_sql
        data[:samples] = serialize_samples(group.samples) if group.samples
      end
      data
    end

    def serialize_samples(samples)
      samples.map do |s|
        {sql: s.sql, duration_ms: s.duration_ms.round(3), allocations: s.allocations}
      end
    end

    def parent_span_label
      tx = RequestContext.transaction_name
      tx ? "view.process_action.action_controller - #{tx}" : nil
    end

    def format_time(t)
      t.respond_to?(:utc) ? t.utc.iso8601(3) : t.to_s
    end
  end
end
