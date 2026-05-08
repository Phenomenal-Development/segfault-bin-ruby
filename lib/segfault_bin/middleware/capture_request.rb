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
      ensure
        SegfaultBin::CurrentRequest.reset
      end
    end
  end
end
