# frozen_string_literal: true

module SegfaultBin
  class Subscriber
    def initialize(client)
      @client = client
    end

    def report(error, handled:, severity:, context:, source: nil)
      return if source.to_s.start_with?("segfault_bin")
      return if error.instance_variable_get(:@__segfault_bin_reported)
      error.instance_variable_set(:@__segfault_bin_reported, true)
      @client.report(error, context: context.merge(
        handled: handled,
        severity: severity,
        source: source
      ))
    end
  end
end
