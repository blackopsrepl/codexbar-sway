# frozen_string_literal: true

require "date"
require "time"

module CodexBar
  module Runtime
    module History
      module_function

      def read_cache(config)
        State.read_history(config)
      end

      def update(config, snapshot, local_usage = nil, now: Time.now.utc)
        return read_cache(config) unless config.dig(:history, :enabled)

        retention_days = config.dig(:history, :retentionDays).to_i
        cutoff = (now.to_date - retention_days + 1).to_s
        history = normalize_history(read_cache(config), retention_days)
        history[:generatedAt] = now.iso8601
        history[:retentionDays] = retention_days
        date = State.generated_time(snapshot)&.utc&.strftime("%Y-%m-%d") || now.utc.strftime("%Y-%m-%d")
        results = State.snapshot_results(snapshot)

        Core::Types::ALL_PROVIDERS.each do |provider|
          provider_history = history[:providers][provider] ||= { provider: provider, daily: [] }
          daily = day_entry(provider_history, date)
          result = results[provider] || results[provider.to_sym]
          merge_usage_day!(daily, result && result[:usage])
          merge_local_usage_day!(daily, local_usage_day(local_usage, provider, date))
          provider_history[:daily] = provider_history[:daily].select { |entry| entry[:date] >= cutoff }.sort_by { |entry| entry[:date] }
        end

        State.write_history(config, history)
        history
      end

      def normalize_history(input, retention_days)
        providers = (input && input[:providers] || {}).each_with_object({}) do |(provider, value), output|
          output[provider.to_s] = {
            provider: provider.to_s,
            daily: Array(value[:daily]).map { |entry| normalize_day(entry) }
          }
        end
        {
          generatedAt: input && input[:generatedAt],
          retentionDays: retention_days,
          providers: providers
        }
      end

      def normalize_day(entry)
        {
          date: entry[:date].to_s,
          primaryMaxUsedPercent: entry[:primaryMaxUsedPercent].to_f,
          secondaryMaxUsedPercent: entry[:secondaryMaxUsedPercent].to_f,
          tertiaryMaxUsedPercent: entry[:tertiaryMaxUsedPercent].to_f,
          latestPrimaryUsedPercent: entry[:latestPrimaryUsedPercent].to_f,
          latestSecondaryUsedPercent: entry[:latestSecondaryUsedPercent].to_f,
          latestTertiaryUsedPercent: entry[:latestTertiaryUsedPercent].to_f,
          totalTokens: entry[:totalTokens].to_i,
          records: entry[:records].to_i,
          cost: entry[:cost],
          modelQuota: normalize_model_quota(entry[:modelQuota]),
          modelUsage: normalize_model_usage(entry[:modelUsage])
        }
      end

      def day_entry(provider_history, date)
        provider_history[:daily].find { |entry| entry[:date] == date } ||
          begin
            entry = normalize_day(date: date)
            provider_history[:daily] << entry
            entry
          end
      end

      def merge_usage_day!(day, usage)
        return unless usage

        if Array(usage[:meters]).any?
          meters = Core::Metric.metric_windows(usage)
          meters.first(3).each_with_index do |window, index|
            merge_window!(day, %i[primary secondary tertiary][index], window)
          end
          meters.each { |window| merge_model_quota!(day, window) }
          return
        end

        merge_window!(day, :primary, usage[:primary])
        merge_window!(day, :secondary, usage[:secondary])
        merge_window!(day, :tertiary, usage[:tertiary])
      end

      def merge_window!(day, key, window)
        return unless window

        value = window[:usedPercent].to_f
        max_key = :"#{key}MaxUsedPercent"
        latest_key = :"latest#{key.to_s.capitalize}UsedPercent"
        day[max_key] = [day[max_key].to_f, value].max
        day[latest_key] = value
      end

      def merge_model_quota!(day, window)
        model_id = window[:modelId].to_s.strip
        model_id = window[:label].to_s.strip if model_id.empty? && window[:key].to_s.start_with?("model:")
        return if model_id.empty?

        value = window[:usedPercent].to_f
        entry = day[:modelQuota][model_id] ||= {
          modelId: model_id,
          label: window[:label].to_s.empty? ? model_id : window[:label].to_s,
          maxUsedPercent: 0.0,
          latestUsedPercent: 0.0
        }
        entry[:maxUsedPercent] = [entry[:maxUsedPercent].to_f, value].max
        entry[:latestUsedPercent] = value
      end

      def merge_local_usage_day!(day, local)
        return unless local

        day[:totalTokens] = local[:totalTokens].to_i
        day[:records] = local[:records].to_i
        day[:cost] = local[:cost] if local.key?(:cost)
        day[:modelUsage] = normalize_model_usage(local[:models]) if local[:models]
      end

      def local_usage_day(local_usage, provider, date)
        provider_usage = local_usage&.dig(:providers, provider) || local_usage&.dig(:providers, provider.to_sym)
        Array(provider_usage && provider_usage[:daily]).find { |entry| entry[:date] == date }
      end

      def normalize_model_quota(input)
        normalize_model_map(input) do |model_id, entry|
          {
            modelId: entry[:modelId].to_s.empty? ? model_id : entry[:modelId].to_s,
            label: entry[:label].to_s.empty? ? model_id : entry[:label].to_s,
            maxUsedPercent: entry[:maxUsedPercent].to_f,
            latestUsedPercent: entry[:latestUsedPercent].to_f
          }
        end
      end

      def normalize_model_usage(input)
        normalize_model_map(input) do |model_id, entry|
          {
            modelId: entry[:modelId].to_s.empty? ? model_id : entry[:modelId].to_s,
            records: entry[:records].to_i,
            inputTokens: entry[:inputTokens].to_i,
            cachedInputTokens: entry[:cachedInputTokens].to_i,
            outputTokens: entry[:outputTokens].to_i,
            reasoningOutputTokens: entry[:reasoningOutputTokens].to_i,
            toolTokens: entry[:toolTokens].to_i,
            totalTokens: entry[:totalTokens].to_i
          }
        end
      end

      def normalize_model_map(input)
        return {} unless input.is_a?(Hash)

        input.each_with_object({}) do |(model_id, entry), output|
          next unless entry.is_a?(Hash)

          key = model_id.to_s
          output[key] = yield(key, entry)
        end
      end
    end
  end
end
