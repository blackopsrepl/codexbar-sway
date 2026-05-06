# frozen_string_literal: true

module CodexBar
  module Runtime
    module Usage
      module_function

      def provider_entries(config)
        Core::Config.normalize_config(config)[:providers]
      end

      def enabled_provider_entries(config)
        provider_entries(config).select { |provider| provider[:enabled] }
      end

      def enabled_providers(config)
        enabled_provider_entries(config).map { |provider| provider[:id] }
      end

      def visible_providers(config, enabled = nil)
        allowed = enabled_provider_ids(enabled, config)
        enabled_provider_entries(config)
          .select { |provider| allowed.include?(provider[:id]) && provider[:visible] }
          .map { |provider| provider[:id] }
      end

      def hidden_providers(config, enabled = nil)
        allowed = enabled_provider_ids(enabled, config)
        enabled_provider_entries(config)
          .select { |provider| allowed.include?(provider[:id]) && !provider[:visible] }
          .map { |provider| provider[:id] }
      end

      def auto_selectable_providers(config, enabled = nil)
        allowed = enabled_provider_ids(enabled, config)
        enabled_provider_entries(config)
          .select { |provider| allowed.include?(provider[:id]) && provider[:visible] && provider[:allowAutoSelect] }
          .map { |provider| provider[:id] }
      end

      def overview_providers(config, enabled = nil)
        allowed = enabled_provider_ids(enabled, config)
        overview_members = enabled_provider_entries(config)
          .select { |provider| allowed.include?(provider[:id]) && provider[:visible] && provider[:showInOverview] }
          .map { |provider| provider[:id] }
        preferred = Array(config.dig(:display, :overviewProviders)).map(&:to_s)
        ordered = preferred.select { |provider| overview_members.include?(provider) }
        ordered.concat(overview_members.reject { |provider| ordered.include?(provider) })
        ordered.first(3)
      end

      def provider_state(config, provider)
        Core::Config.provider_entry(config, provider)
      end

      def collect_usage(config, provider_override = nil)
        providers = provider_override && !provider_override.empty? ? provider_override : enabled_providers(config)
        Providers.fetch_providers(config, providers)
      end

      def selected_provider(config, enabled)
        selected = config.dig(:display, :selectedProvider)
        return selected if enabled.include?(selected)

        visible = visible_providers(config, enabled)
        visible.first || enabled.first
      end

      def display_provider(config, enabled, results)
        return nil if enabled.empty?

        if config.dig(:display, :showHighestUsage)
          usage_map = auto_selectable_providers(config, enabled).each_with_object({}) do |provider, acc|
            result = results[provider] || results[provider.to_sym]
            acc[provider] = result[:usage] if result && result[:usage]
          end
          highest = Core::Metric.highest_usage_provider(usage_map, config.dig(:display, :metricPreferences) || {})
          return highest if highest
        end

        selected_provider(config, enabled)
      end

      def cycle_provider(config, enabled, direction)
        return nil if enabled.empty?

        candidates = visible_providers(config, enabled)
        candidates = enabled if candidates.empty?

        current = if candidates.include?(config.dig(:display, :selectedProvider))
                    config.dig(:display, :selectedProvider)
                  else
                    selected_provider(config, candidates)
                  end
        index = candidates.index(current) || 0
        candidates[(index + direction + candidates.length) % candidates.length]
      end

      def enabled_provider_ids(enabled, config)
        allowed = Array(enabled).map(&:to_s)
        return allowed unless allowed.empty?

        enabled_providers(config)
      end
    end
  end
end
