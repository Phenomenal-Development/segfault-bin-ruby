# frozen_string_literal: true

require "json"
require "net/http"
require "active_support/gzip"
require_relative "../version"

module SegfaultBin
  module Transport
    class SyncHttp
      GZIP_THRESHOLD = 1024

      def initialize(config)
        @config = config
        @endpoint = config.endpoint
      end

      def deliver(payload)
        body = JSON.generate(payload)
        gzipped = body.bytesize > GZIP_THRESHOLD
        body = ActiveSupport::Gzip.compress(body) if gzipped

        Net::HTTP.start(@endpoint.host, @endpoint.port, use_ssl: @endpoint.scheme == "https") do |http|
          req = Net::HTTP::Post.new(@endpoint.path)
          req["Authorization"] = "Bearer #{@config.auth_token}"
          req["Content-Type"] = "application/json"
          req["Content-Encoding"] = "gzip" if gzipped
          req["User-Agent"] = "segfault-bin-ruby/#{VERSION}"
          req["X-Segfault-Bin-Protocol"] = "1"
          req.body = body
          http.request(req)
        end
      end
    end
  end
end
