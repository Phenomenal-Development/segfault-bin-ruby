# frozen_string_literal: true

require "securerandom"
require "time"
require "action_dispatch"
require "active_support/core_ext/string/inflections"
require_relative "version"
require_relative "frame_builder"
require_relative "scrubber"
require_relative "current_request"

module SegfaultBin
  class PayloadBuilder
    SEVERITY_MAP = {
      "debug" => "debug",
      "info" => "info",
      "warning" => "warning",
      "warn" => "warning",
      "error" => "error",
      "fatal" => "fatal"
    }.freeze

    HEADER_ALLOWLIST = %w[
      Accept Accept-Encoding Accept-Language
      Content-Type Content-Length
      Host Origin Referer User-Agent
      X-Forwarded-For X-Forwarded-Proto X-Request-Id
    ].freeze

    def initialize(exception, context, config)
      @exception = exception
      @context = context
      @config = config
    end

    def build
      Scrubber.call({
        event_id: SecureRandom.uuid,
        timestamp: Time.now.utc.iso8601(3),
        level: severity_to_level(@context[:severity]),
        platform: "ruby",
        sdk: {name: "segfault-bin-ruby", version: VERSION},
        environment: @config.environment,
        release: @config.release,
        server_name: @config.server_name,
        exception: build_exception,
        request: build_request,
        user: build_user,
        tags: build_tags,
        extra: @context[:extra] || {},
        breadcrumbs: []
      }, config: @config)
    end

    private

    def build_exception
      mod = @exception.class.name.to_s.deconstantize
      {
        type: @exception.class.name,
        value: @exception.message.to_s,
        module: mod.empty? ? nil : mod,
        frames: FrameBuilder.new(@exception, @config).build
      }
    end

    def build_request
      env = SegfaultBin::CurrentRequest.env
      return {} unless env
      req = ActionDispatch::Request.new(env)
      data = {
        method: req.method,
        url: req.url,
        headers: filtered_headers(req),
        query_string: req.query_string
      }
      data[:params] = filtered_params(req) if @config.include_request_body
      data
    end

    def build_user
      data = {}
      data.merge!(@context[:user]) if @context[:user].is_a?(Hash)
      data.merge!(SegfaultBin::CurrentRequest.user) if SegfaultBin::CurrentRequest.user.is_a?(Hash)

      if @config.send_default_pii && (env = SegfaultBin::CurrentRequest.env)
        data[:ip_address] ||= ActionDispatch::Request.new(env).remote_ip
      end

      result = data.slice(:id, :email, :username, :ip_address).compact
      result.empty? ? nil : result
    end

    def build_tags
      tags = {}
      tags[:handled] = @context[:handled] unless @context[:handled].nil?
      tags[:source] = @context[:source].to_s if @context[:source]
      tags.merge!(@context[:tags]) if @context[:tags].is_a?(Hash)
      tags
    end

    def severity_to_level(severity)
      SEVERITY_MAP[severity.to_s.downcase] || "error"
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
    rescue => _e
      {}
    end
  end
end
