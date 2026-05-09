# frozen_string_literal: true

require "securerandom"
require "time"
require "rbconfig"
require "etc"
require "action_dispatch"
require_relative "version"
require_relative "current_request"

module SegfaultBin
  module RequestContext
    HEADER_ALLOWLIST = %w[
      Accept Accept-Encoding Accept-Language
      Cache-Control Pragma Priority
      Content-Type Content-Length
      Host Origin Referer User-Agent
      Cdn-Loop Cf-Connecting-Ip Cf-Ipcountry Cf-Ray Cf-Visitor
      Sec-Fetch-Dest Sec-Fetch-Mode Sec-Fetch-Site
      X-Forwarded-For X-Forwarded-Port X-Forwarded-Proto
      X-Request-Id X-Request-Start
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
        server_name: config.server_name,
        runtime: runtime_info,
        contexts: contexts(config)
      }
      h[:type] = type if type
      tx = transaction_name
      h[:transaction] = tx if tx
      rid = request_id
      h[:request_id] = rid if rid
      h
    end

    def request_data(config)
      env = SegfaultBin::CurrentRequest.env
      return {} unless env
      req = ActionDispatch::Request.new(env)
      data = {
        method: req.method,
        url: req.url,
        path: req.path,
        host: req.host,
        scheme: req.scheme,
        port: req.port,
        headers: filtered_headers(req),
        query_string: req.query_string,
        env: filtered_env(req)
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

    def transaction_name
      return SegfaultBin::CurrentRequest.transaction if SegfaultBin::CurrentRequest.transaction
      env = SegfaultBin::CurrentRequest.env
      return nil unless env
      params = env["action_dispatch.request.path_parameters"]
      return nil unless params.is_a?(Hash)
      controller = params[:controller] || params["controller"]
      action = params[:action] || params["action"]
      return nil unless controller && action
      "#{camelize_controller(controller.to_s)}##{action}"
    end

    def request_id
      env = SegfaultBin::CurrentRequest.env
      return nil unless env
      env["action_dispatch.request_id"] || env["HTTP_X_REQUEST_ID"]
    end

    def runtime_info
      {
        name: "ruby",
        version: RUBY_VERSION,
        description: "ruby #{RUBY_DESCRIPTION}"
      }
    end

    def contexts(_config)
      ctx = {
        runtime: runtime_info,
        os: os_info
      }
      env = SegfaultBin::CurrentRequest.env
      ua = env && (env["HTTP_USER_AGENT"] || env["User-Agent"])
      browser = parse_browser(ua)
      ctx[:browser] = browser if browser
      client_os = parse_client_os(ua)
      ctx[:client_os] = client_os if client_os
      device = parse_device(ua)
      ctx[:device] = device if device
      ctx
    end

    def os_info
      uname = begin
        Etc.uname
      rescue
        {}
      end
      {
        name: uname[:sysname] || RbConfig::CONFIG["host_os"],
        version: uname[:release],
        build: uname[:version],
        kernel_version: uname[:version]
      }.compact
    end

    def parse_browser(ua)
      return nil unless ua && !ua.empty?
      # Lightweight UA parsing — enough for "Safari 26.4", "Chrome 132.0", "Firefox", "Edge".
      if (m = ua.match(%r{Edg/([\d.]+)}))
        {name: "Edge", version: m[1]}
      elsif (m = ua.match(%r{Firefox/([\d.]+)}))
        {name: "Firefox", version: m[1]}
      elsif (m = ua.match(%r{Chrome/([\d.]+)}))
        {name: "Chrome", version: m[1]}
      elsif (m = ua.match(%r{Version/([\d.]+).+Safari/}))
        {name: "Safari", version: m[1]}
      elsif (m = ua.match(%r{Safari/([\d.]+)}))
        {name: "Safari", version: m[1]}
      end
    end

    def parse_client_os(ua)
      return nil unless ua && !ua.empty?
      if (m = ua.match(/Mac OS X ([\d_.]+)/))
        {name: "Mac OS X", version: m[1].tr("_", ".")}
      elsif ua.include?("Macintosh")
        {name: "Mac OS X"}
      elsif (m = ua.match(/Windows NT ([\d.]+)/))
        {name: "Windows", version: m[1]}
      elsif (m = ua.match(/Android ([\d.]+)/))
        {name: "Android", version: m[1]}
      elsif (m = ua.match(/(?:iPhone|iPad|iPod).+OS ([\d_]+)/))
        {name: "iOS", version: m[1].tr("_", ".")}
      elsif ua.include?("Linux")
        {name: "Linux"}
      end
    end

    def parse_device(ua)
      return nil unless ua && !ua.empty?
      if ua.include?("iPhone")
        {family: "iPhone"}
      elsif ua.include?("iPad")
        {family: "iPad"}
      elsif ua.include?("Android")
        {family: "Android"}
      elsif ua.include?("Macintosh")
        {family: "Mac"}
      elsif ua.include?("Windows")
        {family: "PC"}
      end
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

    def filtered_env(req)
      {
        "SERVER_NAME" => req.env["SERVER_NAME"],
        "SERVER_PORT" => req.env["SERVER_PORT"]
      }.compact
    end

    def filtered_params(req)
      req.parameters.to_h
    rescue
      {}
    end

    def camelize_controller(path)
      path.split("/").map { |part| part.split("_").map(&:capitalize).join }.join("::") + "Controller"
    end
  end
end
