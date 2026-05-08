# frozen_string_literal: true

require_relative "sync_http"

module SegfaultBin
  module Transport
    class AsyncHttp
      QUEUE_SIZE = 100
      SHUTDOWN_TIMEOUT = 2.0
      SHUTDOWN_TOKEN = :__shutdown__
      MAX_ATTEMPTS = 3

      def initialize(config)
        @config = config
        @sync = SyncHttp.new(config)
        @queue = SizedQueue.new(QUEUE_SIZE)
        @dropped_count = 0
        @mutex = Mutex.new
        @at_exit_installed = false
        start_worker
        install_at_exit
      end

      def deliver(payload)
        @queue.push(payload, true)
      rescue ThreadError
        @mutex.synchronize { @dropped_count += 1 }
        warn_drop_periodically
      end

      def flush(timeout: SHUTDOWN_TIMEOUT)
        deadline = Time.now + timeout
        until @queue.empty? || Time.now > deadline
          sleep 0.05
        end
      end

      def shutdown
        return unless @worker&.alive?
        begin
          @queue.push(SHUTDOWN_TOKEN, true)
        rescue ThreadError
        end
        @worker.join(SHUTDOWN_TIMEOUT)
        @worker.kill if @worker.alive?
      end

      private

      def start_worker
        @worker = Thread.new do
          Thread.current.name = "segfault-bin-transport"
          loop do
            payload = @queue.pop
            break if payload == SHUTDOWN_TOKEN
            send_with_retry(payload)
          end
        rescue => e
          @config.logger.error("[SegfaultBin] worker died: #{e.class} #{e.message}")
        end
      end

      def send_with_retry(payload)
        attempts = 0
        loop do
          attempts += 1
          response = @sync.deliver(payload)
          case response.code.to_i
          when 200..299
            return
          when 401, 403, 413
            @config.logger.error("[SegfaultBin] non-retryable response: #{response.code}")
            return
          when 429
            wait = (response["Retry-After"]&.to_f || 30.0)
            sleep([wait, 60].min)
          else
            return if attempts >= MAX_ATTEMPTS
            sleep(backoff(attempts))
          end
        rescue => e
          @config.logger.warn("[SegfaultBin] delivery error (#{attempts}/#{MAX_ATTEMPTS}): #{e.class} #{e.message}")
          return if attempts >= MAX_ATTEMPTS
          sleep(backoff(attempts))
        end
      end

      def backoff(attempt)
        (attempt**2) + rand
      end

      def install_at_exit
        return if @at_exit_installed
        at_exit { shutdown }
        @at_exit_installed = true
      end

      def warn_drop_periodically
        return unless (@dropped_count % 100).zero?
        @config.logger.warn("[SegfaultBin] dropped #{@dropped_count} events (queue full)")
      end
    end
  end
end
