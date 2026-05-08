# frozen_string_literal: true

require_relative "transport/sync_http"
require_relative "transport/async_http"

module SegfaultBin
  module Transport
    def self.build(config)
      if config.async
        AsyncHttp.new(config)
      else
        SyncHttp.new(config)
      end
    end
  end
end
