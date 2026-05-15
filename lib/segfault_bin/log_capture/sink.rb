# frozen_string_literal: true

require "logger"
require_relative "../current_request"

module SegfaultBin
  module LogCapture
    # A Logger-compatible sink that buffers log entries onto a Batcher.
    # Intended to be installed alongside Rails.logger via ActiveSupport::BroadcastLogger.
    class Sink
      LEVEL_NAMES = %w[debug info warn error fatal unknown].freeze

      attr_reader :level

      def initialize(config, batcher:)
        @config = config
        @batcher = batcher
        @level = ::Logger::DEBUG
      end

      # BroadcastLogger calls #add on every wrapped logger. Return true so the
      # broadcast continues regardless of our internal filtering.
      def add(severity, message = nil, progname = nil, &block)
        return true unless @config.logs_enabled?

        sev = severity.to_i
        return true if sev < @config.log_min_severity

        text = format_message(message || (block && block.call) || progname)
        return true if text.empty?

        @batcher.enqueue(build_entry(sev, text))
        true
      rescue => e
        @config.logger&.warn("[SegfaultBin] log sink failed: #{e.class}: #{e.message}")
        true
      end

      # Common Logger convenience helpers — BroadcastLogger forwards via #add,
      # but be defensive so direct calls (sink.info "x") also work.
      def debug(progname = nil, &block);   add(::Logger::DEBUG,   nil, progname, &block); end
      def info(progname  = nil, &block);   add(::Logger::INFO,    nil, progname, &block); end
      def warn(progname  = nil, &block);   add(::Logger::WARN,    nil, progname, &block); end
      def error(progname = nil, &block);   add(::Logger::ERROR,   nil, progname, &block); end
      def fatal(progname = nil, &block);   add(::Logger::FATAL,   nil, progname, &block); end
      def unknown(progname = nil, &block); add(::Logger::UNKNOWN, nil, progname, &block); end

      def debug?;   @config.log_min_severity <= ::Logger::DEBUG; end
      def info?;    @config.log_min_severity <= ::Logger::INFO;  end
      def warn?;    @config.log_min_severity <= ::Logger::WARN;  end
      def error?;   @config.log_min_severity <= ::Logger::ERROR; end
      def fatal?;   @config.log_min_severity <= ::Logger::FATAL; end

      # BroadcastLogger may set #level= on broadcasts; accept it but keep the
      # filtering driven by config.log_min_level (so we never silently capture
      # less than the user asked for).
      def level=(_)
      end

      # No-ops for BroadcastLogger interface completeness.
      def close; end
      def reopen(_logdev = nil); self; end
      def <<(msg); add(::Logger::UNKNOWN, msg); end
      def formatter; nil; end
      def formatter=(_); end
      def progname; nil; end
      def progname=(_); end

      private

      def format_message(value)
        case value
        when nil then ""
        when String then value
        when Exception then "#{value.class}: #{value.message}"
        else value.inspect
        end
      end

      def build_entry(severity, message)
        env = SegfaultBin::CurrentRequest.env
        request_id = env && (env["action_dispatch.request_id"] || env["HTTP_X_REQUEST_ID"])

        {
          occurred_at: Time.now.utc.iso8601(3),
          level:       LEVEL_NAMES[severity] || "unknown",
          message:     message,
          environment: @config.environment,
          release:     @config.release,
          server_name: @config.server_name,
          source:      @config.log_source,
          request_id:  request_id
        }
      end
    end
  end
end
