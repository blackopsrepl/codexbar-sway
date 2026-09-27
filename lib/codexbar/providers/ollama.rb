# frozen_string_literal: true

require "json"
require "time"

module CodexBar
  module Providers
    # Ollama Cloud account usage. Ollama exposes an authenticated usage endpoint
    # at ollama.com/api/usage (Bearer API key) that reports account allowance
    # windows as normalized 0..1 used fractions, not token counts:
    #
    #   { "limits": { "monthly": { "usage": 0.002, "models": [ ... ] } } }
    #
    # Accounts migrated to monthly credits report a single "monthly" window;
    # accounts that have not migrated still report the legacy "session" (5-hour)
    # and "weekly" (7-day) windows. The two shapes are mutually exclusive per
    # account, so a missing key simply yields no window. The payload carries no
    # reset timestamps, so windows stay without a reset time or pace.
    module Ollama
      USAGE_URL = "https://ollama.com/api/usage"
      SESSION_MINUTES = 300
      WEEKLY_MINUTES = 10_080
      MONTHLY_MINUTES = 43_200

      module_function

      def fetch(_config)
        source = "ollama-cloud"
        key = resolve_api_key
        raise "Ollama Cloud API key not found. Set OLLAMA_API_KEY or add an ollama-cloud entry to #{auth_path}." if key.to_s.strip.empty?

        response = Core::Http.request(
          "GET",
          USAGE_URL,
          headers: {
            "Authorization" => "Bearer #{key}",
            "Accept" => "application/json",
            "User-Agent" => "codexbar-linux/1.0"
          }
        )
        raise "Ollama Cloud usage request failed with HTTP #{response.status}." unless response.status.between?(200, 299)

        limits = Core::Http.parse_json(response)[:limits]
        raise "Ollama Cloud usage response did not include allowance windows." unless limits.is_a?(Hash)

        monthly = usage_window(limits[:monthly], MONTHLY_MINUTES, "Monthly", "mo")
        session = usage_window(limits[:session], SESSION_MINUTES, "5-hour", "5h")
        weekly = usage_window(limits[:weekly], WEEKLY_MINUTES, "Weekly", "W")
        raise "Ollama Cloud usage response did not include a usable allowance window." if monthly.nil? && session.nil? && weekly.nil?

        {
          provider: "ollama",
          source: source,
          usage: {
            primary: monthly || session,
            secondary: monthly ? nil : weekly,
            updatedAt: Time.now.utc.iso8601,
            identity: {
              providerID: "ollama",
              loginMethod: "Ollama Cloud"
            }
          },
          notes: []
        }
      rescue StandardError => e
        {
          provider: "ollama",
          source: source,
          notes: [],
          error: e.message
        }
      end

      def usage_window(window, minutes, label, short_label)
        return nil unless window.is_a?(Hash) && !window[:usage].nil?

        {
          label: label,
          shortLabel: short_label,
          usedPercent: clamp(window[:usage].to_f * 100.0, 0.0, 100.0),
          windowMinutes: minutes,
          resetsAt: nil,
          resetDescription: nil
        }
      end

      def resolve_api_key
        [ENV["OLLAMA_API_KEY"], opencode_auth_key].find { |value| value && !value.strip.empty? }&.strip
      end

      def opencode_auth_key
        return nil unless File.file?(auth_path)

        parsed = JSON.parse(File.read(auth_path), symbolize_names: true)
        entry = parsed[:"ollama-cloud"]
        key = entry && entry[:key]
        key.to_s.strip.empty? ? nil : key.to_s.strip
      rescue JSON::ParserError
        nil
      end

      def auth_path
        ENV["CODEXBAR_OPENCODE_AUTH"] || File.join(Dir.home, ".local", "share", "opencode", "auth.json")
      end

      def clamp(value, min, max)
        [[value.to_f, min].max, max].min
      end
    end
  end
end
