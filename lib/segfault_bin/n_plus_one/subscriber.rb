# frozen_string_literal: true

require "active_support/notifications"
require_relative "fingerprinter"
require_relative "call_site_resolver"
require_relative "../current_request"

module SegfaultBin
  module NPlusOne
    class Subscriber
      EVENT_NAME = "sql.active_record"

      class << self
        def attach!(config)
          detach!
          resolver = CallSiteResolver.new(config)
          min_duration_ms = config.n_plus_one_min_duration_ms.to_f
          @subscription = ActiveSupport::Notifications.subscribe(EVENT_NAME) do |_name, start, finish, _id, payload|
            handle(start, finish, payload, resolver, min_duration_ms)
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

        def handle(start, finish, payload, resolver, min_duration_ms)
          return if payload[:cached]
          name = payload[:name]
          return if name == "SCHEMA"
          tracker = SegfaultBin::CurrentRequest.n_plus_one_tracker
          return unless tracker
          sql = payload[:sql]
          return unless sql
          duration_ms = (finish - start) * 1000.0
          return if duration_ms < min_duration_ms
          fp = Fingerprinter.fingerprint(sql)
          call_site = resolver.resolve
          if call_site.nil? || tracker.full?
            tracker.note_query(fingerprint: fp, sql: sql, duration_ms: duration_ms)
            return
          end
          tracker.record(fingerprint: fp, sql: sql, duration_ms: duration_ms, call_site: call_site)
        end
      end
    end
  end
end
