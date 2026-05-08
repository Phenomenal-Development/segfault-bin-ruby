# frozen_string_literal: true

require "active_support/parameter_filter"

module SegfaultBin
  class Scrubber
    DEFAULT_KEYS = %w[password token secret authorization cookie csrf api_key].freeze

    def self.call(payload, config:)
      app_filters = if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
        Rails.application.config.filter_parameters
      else
        []
      end
      keys = DEFAULT_KEYS + config.additional_filter_keys + app_filters
      filter = ActiveSupport::ParameterFilter.new(keys)
      deep_filter(payload, filter)
    end

    def self.deep_filter(node, filter)
      case node
      when Hash then filter.filter(node).transform_values { |v| deep_filter(v, filter) }
      when Array then node.map { |v| deep_filter(v, filter) }
      else node
      end
    end
  end
end
