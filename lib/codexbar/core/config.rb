# frozen_string_literal: true

require "fileutils"
require "json"

module CodexBar
  module Core
    module Config
      CONFIG_VERSION = 4
      DEFAULT_QUICKSHELL_COMMAND = "quickshell"

      module_function

      def default_config
        providers = Types::ALL_PROVIDERS.map { |provider| default_provider_config(provider) }

        {
          version: CONFIG_VERSION,
          providers: providers,
          display: {
            mergeIcons: true,
            showHighestUsage: true,
            showUsed: false,
            resetStyle: "countdown",
            displayMode: "both",
            metricPreferences: {},
            overviewProviders: %w[codex claude gemini],
            selectedProvider: "codex"
          },
          runtime: {
            refreshSeconds: 120,
            notificationCommand: "notify-send",
            stateDir: File.join(Dir.home, ".local", "state", "codexbar"),
            waybarSignal: 9,
            quickShellCommand: DEFAULT_QUICKSHELL_COMMAND,
            quickShellShell: default_quickshell_shell
          }
        }
      end

      def default_config_path
        File.join(Dir.home, ".codexbar", "config.json")
      end

      def load_config(config_path = default_config_path)
        raw = File.read(config_path)
        normalize_config(JSON.parse(raw, symbolize_names: true))
      rescue Errno::ENOENT
        default_config
      end

      def save_config(config, config_path = default_config_path)
        normalized = normalize_config(config)
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, "#{JSON.pretty_generate(normalized)}\n")
        File.chmod(0o600, config_path)
      end

      def init_config(config_path = default_config_path)
        config = normalize_config(default_config)
        save_config(config, config_path)
        config
      end

      def normalize_config(input)
        input ||= {}
        defaults = default_config
        preferred_overview = normalize_providers(input.dig(:display, :overviewProviders))

        providers_by_id = {}
        Array(input[:providers]).each do |provider|
          next unless provider.is_a?(Hash)

          id = clean_string(provider[:id])
          next unless Types.usage_provider?(id)

          providers_by_id[id] = provider.transform_keys(&:to_sym).merge(id: id)
        end

        providers = Types::ALL_PROVIDERS.map do |provider|
          default_entry = defaults[:providers].find { |entry| entry[:id] == provider }
          incoming = providers_by_id[provider] || {}
          show_in_overview_default = if incoming.key?(:showInOverview)
                                       normalize_boolean(incoming[:showInOverview], default_entry[:showInOverview])
                                     else
                                       preferred_overview.include?(provider) || default_entry[:showInOverview]
                                     end

          default_entry.merge(incoming).merge(
            id: provider,
            enabled: normalize_boolean(incoming[:enabled], default_entry[:enabled]),
            visible: normalize_boolean(incoming[:visible], default_entry[:visible]),
            showInOverview: show_in_overview_default,
            allowAutoSelect: normalize_boolean(incoming[:allowAutoSelect], default_entry[:allowAutoSelect]),
            source: clean_string(incoming[:source]) || default_entry[:source]
          )
        end

        overview_providers = derive_overview_providers(providers, preferred_overview)
        {
          version: CONFIG_VERSION,
          providers: providers,
          display: {
            mergeIcons: truthy_or_default(input.dig(:display, :mergeIcons), defaults[:display][:mergeIcons]),
            showHighestUsage: truthy_or_default(input.dig(:display, :showHighestUsage), defaults[:display][:showHighestUsage]),
            showUsed: truthy_or_default(input.dig(:display, :showUsed), defaults[:display][:showUsed]),
            resetStyle: normalize_reset_style(input.dig(:display, :resetStyle)),
            displayMode: normalize_display_mode(input.dig(:display, :displayMode)),
            metricPreferences: normalize_metric_preferences(input.dig(:display, :metricPreferences)),
            overviewProviders: overview_providers.empty? ? defaults[:display][:overviewProviders] : overview_providers,
            selectedProvider: normalize_selected_provider(input.dig(:display, :selectedProvider)) || defaults[:display][:selectedProvider]
          },
          runtime: normalize_runtime(input[:runtime])
        }
      end

      def validate_config(config)
        issues = []

        if config[:version] != CONFIG_VERSION
          issues << {
            severity: "error",
            field: "version",
            message: "Unsupported config version #{config[:version]}. Expected #{CONFIG_VERSION}."
          }
        end

        if config.dig(:runtime, :refreshSeconds).to_i < 15
          issues << {
            severity: "warning",
            field: "runtime.refreshSeconds",
            message: "Refresh below 15 seconds will hammer provider CLIs and APIs."
          }
        end

        quickshell_shell = config.dig(:runtime, :quickShellShell).to_s
        unless File.file?(quickshell_shell)
          issues << {
            severity: "warning",
            field: "runtime.quickShellShell",
            message: "QuickShell shell file not found at #{quickshell_shell}."
          }
        end

        Array(config[:providers]).each do |provider|
          next if Types.usage_provider?(provider[:id])

          issues << {
            severity: "error",
            field: "providers.#{provider[:id]}",
            message: "Unknown provider #{provider[:id]}."
          }
        end

        issues
      end

      def provider_entry(config, provider)
        provider_id = clean_string(provider)
        return nil unless Types.usage_provider?(provider_id)

        normalize_config(config)[:providers].find { |entry| entry[:id] == provider_id }
      end

      def update_provider(config, provider)
        provider_id = clean_string(provider)
        raise ArgumentError, "Unknown provider #{provider}." unless Types.usage_provider?(provider_id)

        normalized = normalize_config(config)
        entry = normalized[:providers].find { |item| item[:id] == provider_id }
        yield(entry)
        normalized[:display][:overviewProviders] = derive_overview_providers(
          normalized[:providers],
          normalized.dig(:display, :overviewProviders)
        )
        normalized
      end

      def set_selected_provider(config, provider)
        provider_id = clean_string(provider)
        raise ArgumentError, "Unknown provider #{provider}." unless Types.usage_provider?(provider_id)

        normalized = normalize_config(config)
        normalized[:display][:selectedProvider] = provider_id
        normalized[:display][:showHighestUsage] = false
        normalized
      end

      def set_highest_usage_mode(config)
        normalized = normalize_config(config)
        normalized[:display][:showHighestUsage] = true
        normalized
      end

      def normalize_runtime(input)
        defaults = default_config[:runtime]
        input = (input || {}).transform_keys(&:to_sym)
        refresh_seconds = input[:refreshSeconds]
        refresh_seconds = refresh_seconds.is_a?(Numeric) ? refresh_seconds : refresh_seconds.to_i
        refresh_seconds = defaults[:refreshSeconds] unless refresh_seconds.positive?

        {
          refreshSeconds: [15, refresh_seconds.round].max,
          notificationCommand: clean_string(input[:notificationCommand]) || defaults[:notificationCommand],
          stateDir: File.expand_path(clean_string(input[:stateDir]) || defaults[:stateDir]),
          waybarSignal: normalize_waybar_signal(input[:waybarSignal], defaults[:waybarSignal]),
          quickShellCommand: clean_string(input[:quickShellCommand]) || defaults[:quickShellCommand],
          quickShellShell: File.expand_path(clean_string(input[:quickShellShell]) || defaults[:quickShellShell])
        }
      end

      def normalize_providers(values)
        seen = {}
        Array(values).filter_map do |value|
          provider = clean_string(value)
          next unless Types.usage_provider?(provider)
          next if seen[provider]

          seen[provider] = true
          provider
        end
      end

      def normalize_selected_provider(value)
        provider = clean_string(value)
        Types.usage_provider?(provider) ? provider : nil
      end

      def normalize_display_mode(value)
        %w[percent pace both].include?(value) ? value : "both"
      end

      def normalize_reset_style(value)
        value == "absolute" ? "absolute" : "countdown"
      end

      def normalize_metric_preferences(input)
        output = {}
        (input || {}).each do |provider, value|
          provider_id = provider.to_s
          next unless Types.usage_provider?(provider_id)
          next unless %w[automatic primary secondary tertiary average].include?(value)

          output[provider_id] = value
        end
        output
      end

      def clean_string(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def truthy_or_default(value, default)
        value.nil? ? default : value
      end

      def normalize_boolean(value, default)
        case value
        when true, 1, "1", "true", "yes", "on"
          true
        when false, 0, "0", "false", "no", "off"
          false
        else
          default
        end
      end

      def normalize_waybar_signal(value, default)
        signal = value.is_a?(Numeric) ? value.to_i : value.to_i
        signal.positive? ? signal : default
      end

      def default_provider_config(provider)
        {
          id: provider,
          enabled: Types::PROVIDER_METADATA.fetch(provider)[:defaultEnabled],
          visible: true,
          showInOverview: default_overview_providers.include?(provider),
          allowAutoSelect: true,
          source: "auto"
        }
      end

      def default_overview_providers
        %w[codex claude gemini]
      end

      def default_quickshell_shell
        File.expand_path("../../../frontend/quickshell/shell.qml", __dir__)
      end

      def derive_overview_providers(providers, preferred_order = nil)
        preferred = normalize_providers(preferred_order)
        overview_members = providers.select { |provider| provider[:showInOverview] }.map { |provider| provider[:id] }
        ordered = preferred.select { |provider| overview_members.include?(provider) }
        ordered.concat(overview_members.reject { |provider| ordered.include?(provider) })
        ordered.first(3)
      end
    end
  end
end
