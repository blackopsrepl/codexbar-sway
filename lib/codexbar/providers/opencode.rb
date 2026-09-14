# frozen_string_literal: true

require "json"
require "time"

module CodexBar
  module Providers
    module Opencode
      USAGE_URL = "https://opencode.ai/zen/go/v1/usage"
      ROLLING_MINUTES = 300
      WEEKLY_MINUTES = 10_080
      MONTHLY_MINUTES = 43_200

      module_function

      def fetch(config)
        source = "opencode-go"
        key = resolve_api_key
        raise "OpenCode Go API key not found in #{auth_path}." if key.to_s.strip.empty?

        response = Core::Http.request(
          "GET",
          USAGE_URL,
          headers: {
            "Authorization" => "Bearer #{key}",
            "Accept" => "application/json",
            "User-Agent" => "codexbar-linux/1.0"
          }
        )
        raise "OpenCode Go usage request failed with HTTP #{response.status}." unless response.status.between?(200, 299)

        payload = Core::Http.parse_json(response)
        windows = payload[:usage]
        raise "OpenCode Go usage response did not include quota windows." unless windows.is_a?(Hash) && !windows.empty?

        usage = {
          primary: make_window(windows[:rolling], ROLLING_MINUTES),
          secondary: make_window(windows[:weekly], WEEKLY_MINUTES),
          tertiary: make_window(windows[:monthly], MONTHLY_MINUTES),
          updatedAt: Time.now.utc.iso8601,
          identity: {
            providerID: "opencode",
            loginMethod: "OpenCode Go"
          }
        }

        {
          provider: "opencode",
          source: source,
          usage: usage,
          notes: []
        }
      rescue StandardError => e
        {
          provider: "opencode",
          source: source,
          notes: [],
          error: e.message
        }
      end

      def make_window(window, minutes)
        return nil unless window && !window[:percent].nil?

        {
          usedPercent: clamp(window[:percent].to_f, 0.0, 100.0),
          windowMinutes: minutes,
          resetsAt: valid_reset_time(window[:resetsAt]),
          resetDescription: nil
        }
      end

      def resolve_api_key
        return nil unless File.file?(auth_path)

        parsed = JSON.parse(File.read(auth_path), symbolize_names: true)
        %w[opencode-go opencode].each do |provider_id|
          entry = parsed[provider_id.to_sym]
          key = entry && entry[:key].to_s.strip
          return key unless key.to_s.empty?
        end

        nil
      rescue JSON::ParserError
        nil
      end

      def auth_path
        ENV["CODEXBAR_OPENCODE_AUTH"] || File.join(Dir.home, ".local", "share", "opencode", "auth.json")
      end

      def valid_reset_time(value)
        return nil if value.to_s.empty?

        time = Time.parse(value.to_s)
        return nil if time.year <= 2000

        time.utc.iso8601
      rescue ArgumentError
        nil
      end

      def clamp(value, min, max)
        [[value.to_f, min].max, max].min
      end
    end
  end
end
