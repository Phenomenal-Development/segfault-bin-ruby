# frozen_string_literal: true

require "active_support/core_ext/string/inflections"
require_relative "frame_builder"
require_relative "scrubber"
require_relative "request_context"

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

    def initialize(exception, context, config)
      @exception = exception
      @context = context
      @config = config
    end

    def build
      payload = RequestContext.envelope(@config, level: severity_to_level(@context[:severity]))
      payload.merge!(
        exception: build_exception,
        request: RequestContext.request_data(@config),
        user: RequestContext.user_data(@config, context_user: @context[:user]),
        tags: build_tags,
        extra: @context[:extra] || {},
        breadcrumbs: []
      )
      Scrubber.call(payload, config: @config)
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
  end
end
