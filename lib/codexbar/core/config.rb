# frozen_string_literal: true

require "fileutils"
require "json"

module CodexBar
  module Core
    module Config
      CONFIG_VERSION = 5
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
            refreshMode: "interval",
            notificationCommand: "notify-send",
            stateDir: File.join(Dir.home, ".local", "state", "codexbar"),
            waybarSignal: 9,
            quickShellCommand: DEFAULT_QUICKSHELL_COMMAND,
            quickShellShell: default_quickshell_shell
          },
          status: {
            enabled: true,
            refreshSeconds: 300
          },
          notifications: {
            enabled: false,
            quotaWarnings: true,
            incidentWarnings: true,
            warningThreshold: 25,
            criticalThreshold: 10,
            restoredThreshold: 30
          },
          history: {
            enabled: true,
            retentionDays: 30
          },
          localUsage: {
            enabled: true,
            refreshSeconds: 900,
            scanDays: 30
          },
          storage: {
            enabled: false,
            refreshSeconds: 3600
          },
          privacy: {
            hidePersonalInfo: false
          },
          server: {
            host: "127.0.0.1",
            port: 8765
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
          runtime: normalize_runtime(input[:runtime]),
          status: normalize_status(input[:status]),
          notifications: normalize_notifications(input[:notifications]),
          history: normalize_history(input[:history]),
          localUsage: normalize_local_usage(input[:localUsage]),
          storage: normalize_storage(input[:storage]),
          privacy: normalize_privacy(input[:privacy]),
          server: normalize_server(input[:server])
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

        if config.dig(:status, :refreshSeconds).to_i < 60
          issues << {
            severity: "warning",
            field: "status.refreshSeconds",
            message: "Status polling below 60 seconds is unnecessarily aggressive."
          }
        end

        if config.dig(:localUsage, :scanDays).to_i < 1
          issues << {
            severity: "error",
            field: "localUsage.scanDays",
            message: "Local usage scan window must be at least 1 day."
          }
        end

        if config.dig(:server, :port).to_i <= 0
          issues << {
            severity: "error",
            field: "server.port",
            message: "Server port must be positive."
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

      def set_refresh_mode(config, mode, seconds = nil)
        normalized = normalize_config(config)
        normalized[:runtime][:refreshMode] = mode == "manual" ? "manual" : "interval"
        normalized[:runtime][:refreshSeconds] = normalize_refresh_seconds(seconds || normalized.dig(:runtime, :refreshSeconds))
        normalized
      end

      def set_notifications_enabled(config, enabled)
        normalized = normalize_config(config)
        normalized[:notifications][:enabled] = !!enabled
        normalized
      end

      def set_privacy_hidden(config, hidden)
        normalized = normalize_config(config)
        normalized[:privacy][:hidePersonalInfo] = !!hidden
        normalized
      end

      def set_status_enabled(config, enabled)
        normalized = normalize_config(config)
        normalized[:status][:enabled] = !!enabled
        normalized
      end

      def set_local_usage_enabled(config, enabled)
        normalized = normalize_config(config)
        normalized[:localUsage][:enabled] = !!enabled
        normalized
      end

      def set_storage_enabled(config, enabled)
        normalized = normalize_config(config)
        normalized[:storage][:enabled] = !!enabled
        normalized
      end

      def normalize_runtime(input)
        defaults = default_config[:runtime]
        input = (input || {}).transform_keys(&:to_sym)
        refresh_seconds = normalize_refresh_seconds(input[:refreshSeconds] || defaults[:refreshSeconds])

        {
          refreshSeconds: refresh_seconds,
          refreshMode: %w[interval manual].include?(input[:refreshMode].to_s) ? input[:refreshMode].to_s : defaults[:refreshMode],
          notificationCommand: clean_string(input[:notificationCommand]) || defaults[:notificationCommand],
          stateDir: File.expand_path(clean_string(input[:stateDir]) || defaults[:stateDir]),
          waybarSignal: normalize_waybar_signal(input[:waybarSignal], defaults[:waybarSignal]),
          quickShellCommand: clean_string(input[:quickShellCommand]) || defaults[:quickShellCommand],
          quickShellShell: File.expand_path(clean_string(input[:quickShellShell]) || defaults[:quickShellShell])
        }
      end

      def normalize_status(input)
        defaults = default_config[:status]
        input = (input || {}).transform_keys(&:to_sym)
        {
          enabled: normalize_boolean(input[:enabled], defaults[:enabled]),
          refreshSeconds: [60, positive_integer(input[:refreshSeconds], defaults[:refreshSeconds])].max
        }
      end

      def normalize_notifications(input)
        defaults = default_config[:notifications]
        input = (input || {}).transform_keys(&:to_sym)
        warning = positive_integer(input[:warningThreshold], defaults[:warningThreshold])
        critical = positive_integer(input[:criticalThreshold], defaults[:criticalThreshold])
        restored = positive_integer(input[:restoredThreshold], defaults[:restoredThreshold])
        {
          enabled: normalize_boolean(input[:enabled], defaults[:enabled]),
          quotaWarnings: normalize_boolean(input[:quotaWarnings], defaults[:quotaWarnings]),
          incidentWarnings: normalize_boolean(input[:incidentWarnings], defaults[:incidentWarnings]),
          warningThreshold: clamp_integer(warning, 1, 100),
          criticalThreshold: clamp_integer(critical, 1, 100),
          restoredThreshold: clamp_integer(restored, 1, 100)
        }
      end

      def normalize_history(input)
        defaults = default_config[:history]
        input = (input || {}).transform_keys(&:to_sym)
        {
          enabled: normalize_boolean(input[:enabled], defaults[:enabled]),
          retentionDays: [1, positive_integer(input[:retentionDays], defaults[:retentionDays])].max
        }
      end

      def normalize_local_usage(input)
        defaults = default_config[:localUsage]
        input = (input || {}).transform_keys(&:to_sym)
        {
          enabled: normalize_boolean(input[:enabled], defaults[:enabled]),
          refreshSeconds: [60, positive_integer(input[:refreshSeconds], defaults[:refreshSeconds])].max,
          scanDays: [1, positive_integer(input[:scanDays], defaults[:scanDays])].max
        }
      end

      def normalize_storage(input)
        defaults = default_config[:storage]
        input = (input || {}).transform_keys(&:to_sym)
        {
          enabled: normalize_boolean(input[:enabled], defaults[:enabled]),
          refreshSeconds: [300, positive_integer(input[:refreshSeconds], defaults[:refreshSeconds])].max
        }
      end

      def normalize_privacy(input)
        defaults = default_config[:privacy]
        input = (input || {}).transform_keys(&:to_sym)
        {
          hidePersonalInfo: normalize_boolean(input[:hidePersonalInfo], defaults[:hidePersonalInfo])
        }
      end

      def normalize_server(input)
        defaults = default_config[:server]
        input = (input || {}).transform_keys(&:to_sym)
        {
          host: clean_string(input[:host]) || defaults[:host],
          port: positive_integer(input[:port], defaults[:port])
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

      def normalize_refresh_seconds(value)
        refresh_seconds = value.is_a?(Numeric) ? value : value.to_i
        refresh_seconds = default_config.dig(:runtime, :refreshSeconds) unless refresh_seconds.positive?
        [15, refresh_seconds.round].max
      end

      def positive_integer(value, default)
        number = value.is_a?(Numeric) ? value.to_i : value.to_i
        number.positive? ? number : default
      end

      def clamp_integer(value, min, max)
        [[value.to_i, min].max, max].min
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
