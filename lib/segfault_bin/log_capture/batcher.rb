# frozen_string_literal: true

require "json"
require "net/http"
require "active_support/gzip"
require_relative "../version"

module SegfaultBin
  module LogCapture
    # Background batcher: accepts log entries on the caller thread, buffers
    # them, and flushes batches over HTTP from a dedicated worker thread.
    class Batcher
      GZIP_THRESHOLD = 1024
      DISABLED_BACKOFF = 60.0 # seconds after server returns 204 (logs_enabled=false)

      def initialize(config)
        @config = config
        @endpoint = config.endpoint
        @buffer = []
        @mutex = Mutex.new
        @cond = ConditionVariable.new
        @dropped = 0
        @shutdown = false
        @disabled_until = nil
        @worker = nil
      end

      def start
        @mutex.synchronize do
          return if @worker&.alive?
          @shutdown = false
          @worker = Thread.new { worker_loop }
          @worker.name = "segfault-bin-log-batcher"
        end
        install_at_exit
      end

      def enqueue(entry)
        return unless entry
        @mutex.synchronize do
          if @buffer.size >= @config.log_max_buffer
            @dropped += 1
            warn_drop_periodically
            return
          end
          @buffer << entry
          @cond.signal if @buffer.size >= @config.log_batch_size
        end
      end

      def flush(timeout: 2.0)
        deadline = Time.now + timeout
        loop do
          batch = pop_batch
          break if batch.empty?
          deliver(batch)
          break if Time.now > deadline
        end
      end

      def shutdown
        @mutex.synchronize do
          @shutdown = true
          @cond.broadcast
        end
        @worker&.join(2.0)
        @worker.kill if @worker&.alive?
        flush(timeout: 1.0)
      end

      private

      def worker_loop
        loop do
          batch = wait_for_batch
          break if batch.nil?
          deliver(batch) unless batch.empty?
        end
      rescue => e
        @config.logger.error("[SegfaultBin] log batcher died: #{e.class}: #{e.message}")
      end

      def wait_for_batch
        @mutex.synchronize do
          loop do
            return nil if @shutdown && @buffer.empty?
            return pop_batch_unlocked if @buffer.size >= @config.log_batch_size
            return pop_batch_unlocked if @shutdown
            return pop_batch_unlocked unless @buffer.empty? && wait_with_timeout
          end
        end
      end

      # Returns true if the timeout elapsed (i.e., flush due to interval).
      def wait_with_timeout
        @cond.wait(@mutex, @config.log_flush_interval)
        false
      end

      def pop_batch
        @mutex.synchronize { pop_batch_unlocked }
      end

      def pop_batch_unlocked
        size = [ @buffer.size, @config.log_batch_size ].min
        @buffer.shift(size)
      end

      def deliver(batch)
        return if batch.empty?
        return if disabled?

        # A log batch has no event envelope, so it names the gem itself: the
        # collector records the version off any message a project sends, and
        # log shipping is often the only thing a healthy app ever sends.
        body = JSON.generate(sdk: {name: "segfault-bin-ruby", version: VERSION}, logs: batch)
        gzipped = body.bytesize > GZIP_THRESHOLD
        body = ActiveSupport::Gzip.compress(body) if gzipped

        response = Net::HTTP.start(@endpoint.host, @endpoint.port, use_ssl: @endpoint.scheme == "https") do |http|
          req = Net::HTTP::Post.new(@config.log_endpoint_path)
          req["Authorization"] = "Bearer #{@config.auth_token}"
          req["Content-Type"] = "application/json"
          req["Content-Encoding"] = "gzip" if gzipped
          req["User-Agent"] = "segfault-bin-ruby/#{VERSION}"
          req["X-Segfault-Bin-Version"] = VERSION
          req["X-Segfault-Bin-Protocol"] = "1"
          req.body = body
          http.request(req)
        end

        handle_response(response, batch_size: batch.size)
      rescue StandardError, SystemCallError, IOError => e
        @config.logger.warn("[SegfaultBin] log delivery failed: #{e.class}: #{e.message}")
      end

      def handle_response(response, batch_size:)
        code = response.code.to_i
        case code
        when 204
          @disabled_until = Time.now + DISABLED_BACKOFF
          @config.logger.info("[SegfaultBin] server reports logs disabled — backing off for #{DISABLED_BACKOFF}s")
        when 200..299
          # ok
        when 401, 403
          @config.logger.error("[SegfaultBin] log auth failed (#{code}); pausing for #{DISABLED_BACKOFF}s")
          @disabled_until = Time.now + DISABLED_BACKOFF
        when 413
          @config.logger.error("[SegfaultBin] log batch too large (#{batch_size} entries) — consider lowering log_batch_size")
        when 429
          wait = (response["Retry-After"]&.to_f || 30.0)
          @disabled_until = Time.now + [ wait, 60 ].min
        else
          @config.logger.warn("[SegfaultBin] log delivery got HTTP #{code}")
        end
      end

      def disabled?
        return false unless @disabled_until
        if Time.now < @disabled_until
          true
        else
          @disabled_until = nil
          false
        end
      end

      def warn_drop_periodically
        return unless (@dropped % 100).zero?
        @config.logger.warn("[SegfaultBin] dropped #{@dropped} log entries (buffer full)")
      end

      def install_at_exit
        return if @at_exit_installed
        at_exit { shutdown }
        @at_exit_installed = true
      end
    end
  end
end
