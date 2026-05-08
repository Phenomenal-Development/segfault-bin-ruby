# frozen_string_literal: true

module SegfaultBin
  class FrameBuilder
    CONTEXT_LINES = 5

    def initialize(exception, config)
      @exception = exception
      @config = config
      raw_root = (config.app_dirs_pattern || (defined?(Rails) && Rails.root) || Dir.pwd).to_s
      @app_root = File.exist?(raw_root) ? File.realpath(raw_root) : raw_root
      @bundle_root = (Bundler.bundle_path.to_s if defined?(Bundler))
    end

    def build
      locations = @exception.backtrace_locations
      return build_from_strings(@exception.backtrace || []) unless locations
      locations.map { |loc| build_frame(loc) }.compact.reverse
    end

    private

    def build_frame(loc)
      abs_path = loc.absolute_path || loc.path
      filename = abs_path.delete_prefix("#{@app_root}/")
      in_app = abs_path.start_with?(@app_root) && !abs_path.include?("/vendor/") &&
        (@bundle_root.nil? || !abs_path.start_with?(@bundle_root))

      frame = {
        filename: filename,
        function: loc.label,
        lineno: loc.lineno,
        abs_path: abs_path,
        in_app: in_app
      }
      add_source_context(frame, abs_path, loc.lineno) if in_app
      frame
    end

    def add_source_context(frame, path, lineno)
      return unless File.exist?(path)
      lines = File.readlines(path)
      idx = lineno - 1
      frame[:pre_context] = lines[[idx - CONTEXT_LINES, 0].max...idx].map(&:rstrip)
      frame[:context_line] = lines[idx]&.rstrip
      frame[:post_context] = lines[(idx + 1)..(idx + CONTEXT_LINES)]&.map(&:rstrip) || []
    rescue => e
      @config.logger.warn("[SegfaultBin] failed to read #{path}: #{e.message}")
    end

    def build_from_strings(backtrace)
      backtrace.map do |line|
        if line =~ /\A(.+?):(\d+)(?::in [`'](.+?)')?\z/
          {filename: $1, lineno: $2.to_i, function: $3 || "?", abs_path: $1, in_app: $1.start_with?(@app_root)}
        end
      end.compact.reverse
    end
  end
end
