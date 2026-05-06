# frozen_string_literal: true

module CodexBar
  module Core
    module Types
      ALL_PROVIDERS = %w[
        codex
        claude
        gemini
      ].freeze

      PROVIDER_METADATA = {
        "codex" => { label: "Codex", shortLabel: "CX", sessionLabel: "Session", weeklyLabel: "Weekly", defaultEnabled: false, supportsAverage: false, supportsTertiary: false, accent: "#82FB9C", icon: "󰚩", dashboardUrl: "https://chatgpt.com/codex" },
        "claude" => { label: "Claude", shortLabel: "CL", sessionLabel: "Session", weeklyLabel: "Weekly", tertiaryLabel: "Sonnet", defaultEnabled: false, supportsAverage: false, supportsTertiary: true, accent: "#F2C572", icon: "", dashboardUrl: "https://claude.ai/" },
        "gemini" => { label: "Gemini", shortLabel: "GM", sessionLabel: "Pro", weeklyLabel: "Flash", defaultEnabled: false, supportsAverage: true, supportsTertiary: false, accent: "#82A7F4", icon: "", dashboardUrl: "https://gemini.google.com/" }
      }.freeze

      module_function

      def usage_provider?(value)
        ALL_PROVIDERS.include?(value)
      end

      def provider_config_for(config, provider)
        found = config[:providers].find { |entry| entry[:id] == provider }
        found || { id: provider, enabled: PROVIDER_METADATA.fetch(provider)[:defaultEnabled] }
      end

      def rate_window_remaining_percent(window)
        return nil unless window

        [0, 100 - window[:usedPercent].to_f].max
      end
    end
  end
end
