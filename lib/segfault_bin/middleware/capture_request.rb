# frozen_string_literal: true

require_relative "../current_request"
require_relative "../n_plus_one/tracker"
require_relative "../slow_query/tracker"

module SegfaultBin
  module Middleware
    class CaptureRequest
      def initialize(app)
        @app = app
      end

      def call(env)
        SegfaultBin::CurrentRequest.env = env
        cfg = SegfaultBin.config
        if cfg.enabled? && cfg.detect_n_plus_one
          SegfaultBin::CurrentRequest.n_plus_one_tracker = SegfaultBin::NPlusOne::Tracker.new(
            threshold: cfg.n_plus_one_threshold,
            max_groups: cfg.n_plus_one_max_groups
          )
        end
        if cfg.enabled? && cfg.detect_slow_queries
          SegfaultBin::CurrentRequest.slow_query_tracker = SegfaultBin::SlowQuery::Tracker.new(
            max_groups: cfg.slow_query_max_groups
          )
        end
        result = @app.call(env)
        flush_n_plus_one
        flush_slow_queries
        result
      rescue Exception => e
        unless e.instance_variable_get(:@__segfault_bin_reported)
          e.instance_variable_set(:@__segfault_bin_reported, true)
          SegfaultBin.report(e, context: {handled: false, source: "rack.middleware"})
        end
        raise
      ensure
        SegfaultBin::CurrentRequest.reset
      end

      private

      def flush_n_plus_one
        tracker = SegfaultBin::CurrentRequest.n_plus_one_tracker
        return unless tracker
        return if tracker.empty?
        SegfaultBin.report_n_plus_one(tracker.triggered_groups, truncated: tracker.full?)
      rescue => e
        SegfaultBin.config.logger.error("[SegfaultBin] n+1 flush failed: #{e.class} #{e.message}")
      end

      def flush_slow_queries
        tracker = SegfaultBin::CurrentRequest.slow_query_tracker
        return unless tracker
        return if tracker.empty?
        SegfaultBin.report_slow_queries(tracker.groups, truncated: tracker.full?)
      rescue => e
        SegfaultBin.config.logger.error("[SegfaultBin] slow query flush failed: #{e.class} #{e.message}")
      end
    end
  end
end
