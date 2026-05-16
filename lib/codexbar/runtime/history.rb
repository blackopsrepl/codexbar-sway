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
          cost: entry[:cost]
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

      def merge_local_usage_day!(day, local)
        return unless local

        day[:totalTokens] = local[:totalTokens].to_i
        day[:records] = local[:records].to_i
        day[:cost] = local[:cost] if local.key?(:cost)
      end

      def local_usage_day(local_usage, provider, date)
        provider_usage = local_usage&.dig(:providers, provider) || local_usage&.dig(:providers, provider.to_sym)
        Array(provider_usage && provider_usage[:daily]).find { |entry| entry[:date] == date }
      end
    end
  end
end
