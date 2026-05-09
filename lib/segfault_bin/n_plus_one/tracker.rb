# frozen_string_literal: true

module SegfaultBin
  module NPlusOne
    class Tracker
      Group = Struct.new(
        :fingerprint, :call_site, :count, :total_duration_ms,
        :sample_sql, :first_seen_at, :last_seen_at, :triggered,
        keyword_init: true
      )

      DEFAULT_THRESHOLD = 5
      DEFAULT_MAX_GROUPS = 1000

      def initialize(threshold: DEFAULT_THRESHOLD, max_groups: DEFAULT_MAX_GROUPS, clock: Time)
        @threshold = threshold
        @max_groups = max_groups
        @clock = clock
        @groups = {}
        @triggered = []
        @full = false
      end

      def record(fingerprint:, sql:, duration_ms:, call_site:)
        key = [fingerprint, call_site]
        group = @groups[key]
        if group.nil?
          return if @full
          if @groups.size >= @max_groups
            @full = true
            return
          end
          now = @clock.now
          group = Group.new(
            fingerprint: fingerprint,
            call_site: call_site,
            count: 0,
            total_duration_ms: 0.0,
            sample_sql: sql,
            first_seen_at: now,
            last_seen_at: now,
            triggered: false
          )
          @groups[key] = group
        end
        group.count += 1
        group.total_duration_ms += duration_ms
        group.last_seen_at = @clock.now
        if !group.triggered && group.count >= @threshold
          group.triggered = true
          @triggered << key
        end
        nil
      end

      def triggered_groups
        @triggered.map { |k| @groups.fetch(k) }
      end

      def full?
        @full
      end

      def empty?
        @triggered.empty?
      end
    end
  end
end
