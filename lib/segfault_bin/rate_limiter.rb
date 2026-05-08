# frozen_string_literal: true

module SegfaultBin
  class RateLimiter
    def initialize(limit_per_minute)
      @limit = limit_per_minute
      @timestamps = []
      @mutex = Mutex.new
    end

    def throttled?
      @mutex.synchronize do
        now = Time.now.to_f
        @timestamps.reject! { |t| t < now - 60 }
        return true if @timestamps.size >= @limit
        @timestamps << now
        false
      end
    end
  end
end
