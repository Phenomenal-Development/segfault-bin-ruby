# frozen_string_literal: true

require "set"

module SegfaultBin
  module SlowQuery
    class Tracker
      KIND_SLOW = :slow_duration
      KIND_HEAVY = :high_allocations

      Group = Struct.new(
        :fingerprint, :call_site, :count,
        :total_duration_ms, :max_duration_ms,
        :total_allocations, :max_allocations,
        :kinds, :sample_sql, :samples,
        :first_seen_at, :last_seen_at,
        keyword_init: true
      )

      Sample = Struct.new(:sql, :duration_ms, :allocations, keyword_init: true)

      DEFAULT_MAX_GROUPS = 200
      MAX_SAMPLES_PER_GROUP = 5

      def initialize(max_groups: DEFAULT_MAX_GROUPS, clock: Time)
        @max_groups = max_groups
        @clock = clock
        @groups = {}
        @full = false
      end

      def record(fingerprint:, sql:, duration_ms:, allocations:, slow:, heavy:, call_site:)
        key = [fingerprint, call_site[:filename], call_site[:lineno]]
        group = @groups[key]
        if group.nil?
          if @full || @groups.size >= @max_groups
            @full = true
            return
          end
          now = @clock.now
          group = Group.new(
            fingerprint: fingerprint,
            call_site: call_site,
            count: 0,
            total_duration_ms: 0.0,
            max_duration_ms: 0.0,
            total_allocations: 0,
            max_allocations: 0,
            kinds: Set.new,
            sample_sql: sql,
            samples: [],
            first_seen_at: now,
            last_seen_at: now
          )
          @groups[key] = group
        end
        group.count += 1
        group.total_duration_ms += duration_ms
        group.max_duration_ms = duration_ms if duration_ms > group.max_duration_ms
        group.total_allocations += allocations
        group.max_allocations = allocations if allocations > group.max_allocations
        group.kinds << KIND_SLOW if slow
        group.kinds << KIND_HEAVY if heavy
        group.last_seen_at = @clock.now
        if group.samples.size < MAX_SAMPLES_PER_GROUP
          group.samples << Sample.new(sql: sql, duration_ms: duration_ms, allocations: allocations)
        end
        nil
      end

      def groups
        @groups.values
      end

      def full?
        @full
      end

      def empty?
        @groups.empty?
      end
    end
  end
end
