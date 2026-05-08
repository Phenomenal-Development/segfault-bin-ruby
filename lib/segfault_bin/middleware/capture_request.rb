# frozen_string_literal: true

require_relative "../current_request"

module SegfaultBin
  module Middleware
    class CaptureRequest
      def initialize(app)
        @app = app
      end

      def call(env)
        SegfaultBin::CurrentRequest.env = env
        @app.call(env)
      rescue Exception => e
        unless e.instance_variable_get(:@__segfault_bin_reported)
          e.instance_variable_set(:@__segfault_bin_reported, true)
          SegfaultBin.report(e, context: {handled: false, source: "rack.middleware"})
        end
        raise
      ensure
        SegfaultBin::CurrentRequest.reset
      end
    end
  end
end
