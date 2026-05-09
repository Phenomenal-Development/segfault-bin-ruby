# frozen_string_literal: true

require "securerandom"
require "time"
require "action_dispatch"
require_relative "version"
require_relative "current_request"

module SegfaultBin
  module RequestContext
    HEADER_ALLOWLIST = %w[
      Accept Accept-Encoding Accept-Language
      Content-Type Content-Length
      Host Origin Referer User-Agent
      X-Forwarded-For X-Forwarded-Proto X-Request-Id
    ].freeze

    module_function

    def envelope(config, level:, type: nil)
      h = {
        event_id: SecureRandom.uuid,
        timestamp: Time.now.utc.iso8601(3),
        level: level,
        platform: "ruby",
        sdk: {name: "segfault-bin-ruby", version: VERSION},
        environment: config.environment,
        release: config.release,
        server_name: config.server_name
      }
      h[:type] = type if type
      h
    end

    def request_data(config)
      env = SegfaultBin::CurrentRequest.env
      return {} unless env
      req = ActionDispatch::Request.new(env)
      data = {
        method: req.method,
        url: req.url,
        headers: filtered_headers(req),
        query_string: req.query_string
      }
      data[:params] = filtered_params(req) if config.include_request_body
      data
    end

    def user_data(config, context_user: nil)
      data = {}
      data.merge!(context_user) if context_user.is_a?(Hash)
      data.merge!(SegfaultBin::CurrentRequest.user) if SegfaultBin::CurrentRequest.user.is_a?(Hash)

      if config.send_default_pii && (env = SegfaultBin::CurrentRequest.env)
        data[:ip_address] ||= ActionDispatch::Request.new(env).remote_ip
      end

      data.slice(:id, :email, :username, :ip_address).compact
    end

    def filtered_headers(req)
      headers = {}
      req.env.each do |key, value|
        next unless key.is_a?(String)
        name = if key.start_with?("HTTP_")
          key.sub("HTTP_", "").split("_").map(&:capitalize).join("-")
        elsif %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
          key.split("_").map(&:capitalize).join("-")
        end
        next unless name
        next unless HEADER_ALLOWLIST.include?(name)
        headers[name] = value.to_s
      end
      headers
    end

    def filtered_params(req)
      req.parameters.to_h
    rescue
      {}
    end
  end
end
