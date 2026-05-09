# frozen_string_literal: true

module SegfaultBin
  module NPlusOne
    class CallSiteResolver
      MAX_FRAMES = 30
      START_FRAME = 2

      def initialize(config)
        @config = config
        raw_root = (config.app_dirs_pattern || (defined?(Rails) && Rails.root) || Dir.pwd).to_s
        @app_root = File.exist?(raw_root) ? File.realpath(raw_root) : raw_root
        @bundle_root = (Bundler.bundle_path.to_s if defined?(Bundler))
      end

      def resolve
        locations = caller_locations(START_FRAME, MAX_FRAMES) || []
        locations.each do |loc|
          abs_path = loc.absolute_path || loc.path
          next unless abs_path
          next unless in_app?(abs_path)
          return {
            abs_path: abs_path,
            filename: abs_path.delete_prefix("#{@app_root}/"),
            lineno: loc.lineno,
            function: loc.label,
            in_app: true
          }
        end
        nil
      end

      private

      def in_app?(abs_path)
        return false unless abs_path.start_with?(@app_root)
        return false if abs_path.include?("/vendor/")
        return false if @bundle_root && abs_path.start_with?(@bundle_root)
        true
      end
    end
  end
end
