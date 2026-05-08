# frozen_string_literal: true

module SegfaultBin
  class Subscriber
    def initialize(client)
      @client = client
    end

    def report(error, handled:, severity:, context:, source: nil)
      return if source.to_s.start_with?("segfault_bin")
      @client.report(error, context: context.merge(
        handled: handled,
        severity: severity,
        source: source
      ))
    end
  end
end
