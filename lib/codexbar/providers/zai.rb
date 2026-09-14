# frozen_string_literal: true

require "json"
require "time"

module CodexBar
  module Providers
    module Zai
      QUOTA_URL = "https://api.z.ai/api/monitor/usage/quota/limit"
      SESSION_MINUTES = 300
      WEEKLY_MINUTES = 10_080
      TOOLS_MINUTES = 43_200
      QUOTA_WINDOW_TYPES = %w[TOKENS_LIMIT CREDIT_LIMIT].freeze
      UNIT_SESSION = 3
      UNIT_WEEKLY = 6

      module_function

      def fetch(_config)
        source = "zai-coding-plan"
        key = resolve_api_key
        raise "Z.ai API key not found. Set ZAI_API_KEY or add a zai-coding-plan entry to #{auth_path}." if key.to_s.strip.empty?

        response = Core::Http.request(
          "GET",
          QUOTA_URL,
          headers: {
            "Authorization" => "Bearer #{key}",
            "Accept" => "application/json",
            "User-Agent" => "codexbar-linux/1.0"
          }
        )
        raise "Z.ai quota request failed with HTTP #{response.status}." unless response.status.between?(200, 299)

        data = Core::Http.parse_json(response)[:data]
        limits = Array(data && data[:limits]).select { |limit| limit.is_a?(Hash) }
        session = quota_window(limits, UNIT_SESSION)
        weekly = quota_window(limits, UNIT_WEEKLY)
        raise "Z.ai quota response did not include usable token quota windows." if session.nil? && weekly.nil?

        {
          provider: "zai",
          source: source,
          usage: {
            primary: make_window(session, SESSION_MINUTES),
            secondary: make_window(weekly, WEEKLY_MINUTES),
            tertiary: make_window(time_limit(limits), TOOLS_MINUTES),
            updatedAt: Time.now.utc.iso8601,
            identity: {
              providerID: "zai",
              loginMethod: identity_label(data[:level])
            }
          },
          notes: []
        }
      rescue StandardError => e
        {
          provider: "zai",
          source: source,
          notes: [],
          error: e.message
        }
      end

      def quota_window(limits, unit)
        limits.find do |limit|
          QUOTA_WINDOW_TYPES.include?(limit[:type].to_s) &&
            limit[:unit].to_i == unit &&
            !limit[:percentage].nil?
        end
      end

      def time_limit(limits)
        limits.find { |limit| limit[:type].to_s == "TIME_LIMIT" && !limit[:percentage].nil? }
      end

      def make_window(limit, minutes)
        return nil unless limit

        {
          usedPercent: clamp(limit[:percentage].to_f, 0.0, 100.0),
          windowMinutes: minutes,
          resetsAt: reset_time_iso(limit[:nextResetTime]),
          resetDescription: nil
        }
      end

      def reset_time_iso(value)
        milliseconds = value.to_i
        return nil if milliseconds <= 0

        time = Time.at(milliseconds / 1000.0)
        time.year > 2000 ? time.utc.iso8601 : nil
      rescue RangeError
        nil
      end

      def identity_label(level)
        plan = level.to_s.strip
        plan.empty? ? "GLM Coding Plan" : "GLM Coding Plan (#{plan})"
      end

      def resolve_api_key
        [ENV["ZAI_API_KEY"], ENV["GLM_API_KEY"], opencode_auth_key].find do |value|
          value && !value.strip.empty?
        end&.strip
      end

      def opencode_auth_key
        return nil unless File.file?(auth_path)

        parsed = JSON.parse(File.read(auth_path), symbolize_names: true)
        entry = parsed[:"zai-coding-plan"] || parsed[:zai]
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
