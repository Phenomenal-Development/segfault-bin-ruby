# frozen_string_literal: true

require "active_support/notifications"
require_relative "../n_plus_one/fingerprinter"
require_relative "../n_plus_one/call_site_resolver"
require_relative "../current_request"

module SegfaultBin
  module SlowQuery
    class Subscriber
      EVENT_NAME = "sql.active_record"

      class << self
        def attach!(config)
          detach!
          resolver = NPlusOne::CallSiteResolver.new(config)
          min_ms = config.slow_query_min_duration_ms.to_f
          min_alloc = config.slow_query_min_allocations.to_i
          @subscription = ActiveSupport::Notifications.subscribe(EVENT_NAME) do |event|
            handle(event, resolver, min_ms, min_alloc)
          end
        end

        def detach!
          if @subscription
            ActiveSupport::Notifications.unsubscribe(@subscription)
            @subscription = nil
          end
        end

        def attached?
          !@subscription.nil?
        end

        def handle(event, resolver, min_ms, min_alloc)
          payload = event.payload
          return if payload[:cached]
          return if payload[:name] == "SCHEMA"
          duration_ms = event.duration.to_f
          allocations = event.respond_to?(:allocations) ? event.allocations.to_i : 0
          slow = duration_ms >= min_ms
          heavy = allocations >= min_alloc
          return unless slow || heavy
          tracker = SegfaultBin::CurrentRequest.slow_query_tracker
          return unless tracker
          return if tracker.full?
          sql = payload[:sql]
          return unless sql
          call_site = resolver.resolve
          return if call_site.nil?
          fp = NPlusOne::Fingerprinter.fingerprint(sql)
          tracker.record(
            fingerprint: fp,
            sql: sql,
            duration_ms: duration_ms,
            allocations: allocations,
            slow: slow,
            heavy: heavy,
            call_site: call_site
          )
        end
      end
    end
  end
end
