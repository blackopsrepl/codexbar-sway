# frozen_string_literal: true

module CodexBar
  module Core
    module Metric
      module_function

      def resolve_metric_preference(provider, snapshot, preference)
        value = preference || "automatic"
        metadata = Types::PROVIDER_METADATA.fetch(provider)
        return "automatic" if value == "average" && !metadata[:supportsAverage]
        return "automatic" if value == "tertiary" && !metadata[:supportsTertiary]

        value
      end

      def resolve_metric_window(provider, snapshot, preference)
        return {} unless snapshot

        effective = resolve_metric_preference(provider, snapshot, preference)
        primary = snapshot[:primary]
        secondary = snapshot[:secondary]
        tertiary = snapshot[:tertiary]

        window = case effective
                 when "primary"
                   ordered_window([primary, tertiary, secondary])
                 when "secondary"
                   ordered_window([secondary, primary, tertiary])
                 when "tertiary"
                   ordered_window([tertiary, primary, secondary])
                 when "average"
                   if primary && secondary
                     { usedPercent: (primary[:usedPercent].to_f + secondary[:usedPercent].to_f) / 2.0 }
                   else
                     primary || secondary
                   end
                 else
                   automatic_window(provider, snapshot)
                 end

        { effective: effective, window: window, pace: window ? usage_pace(window) : nil }
      end

      def compact_display_text(mode, resolved, show_used)
        percent = percent_text(resolved[:window], show_used)
        pace = pace_text(resolved[:pace])
        return percent if mode == "percent"
        return pace || percent if mode == "pace"
        return pace unless percent

        pace ? "#{percent} #{pace}" : percent
      end

      def highest_usage_provider(snapshots, metric_preferences)
        best = nil

        snapshots.each do |provider, snapshot|
          metric = resolve_metric_window(provider, snapshot, metric_preferences[provider])
          used_percent = metric.dig(:window, :usedPercent).to_f
          best = { provider: provider, usedPercent: used_percent } if best.nil? || used_percent > best[:usedPercent]
        end

        best&.dig(:provider)
      end

      def pace_summary_text(window)
        pace = usage_pace(window)
        return nil unless pace

        delta_value = pace[:deltaPercent].abs.round
        left = pace[:deltaPercent] >= 0 ? "#{delta_value}% in deficit" : "#{delta_value}% in reserve"
        return pace[:willLastToReset] ? "On pace · Lasts until reset" : "On pace" if pace[:deltaPercent].abs <= 2
        return "#{left} · Lasts until reset" if pace[:willLastToReset]
        return "#{left} · Runs out in #{duration_text(pace[:etaSeconds])}" if pace[:etaSeconds]

        left
      end

      def percent_text(window, show_used)
        return nil unless window

        value = show_used ? window[:usedPercent].to_f : [0, 100 - window[:usedPercent].to_f].max
        "#{clamp(value, 0, 100).round}%"
      end

      def pace_text(pace)
        return nil unless pace

        state = pace_state(pace)
        return nil unless state
        return "on pace" if state == "even"

        state
      end

      def pace_state(pace)
        return nil unless pace

        delta = pace[:deltaPercent].abs.round
        return "even" if delta <= 2

        pace[:deltaPercent] >= 0 ? "hot" : "reserve"
      end

      def remaining_percent(window)
        Types.rate_window_remaining_percent(window)
      end

      def quota_level(window, warning_threshold:, critical_threshold:)
        remaining = remaining_percent(window)
        return nil unless remaining
        return "critical" if remaining <= critical_threshold.to_f
        return "warning" if remaining <= warning_threshold.to_f

        "ok"
      end

      def worst_quota_level(windows, warning_threshold:, critical_threshold:)
        levels = Array(windows).filter_map do |window|
          quota_level(window, warning_threshold: warning_threshold, critical_threshold: critical_threshold)
        end
        return nil if levels.empty?
        return "critical" if levels.include?("critical")
        return "warning" if levels.include?("warning")

        "ok"
      end

      def automatic_window(_provider, snapshot)
        snapshot[:primary] || snapshot[:secondary] || snapshot[:tertiary]
      end

      def ordered_window(windows)
        windows.compact.first
      end

      def usage_pace(window)
        resets_at = window[:resetsAt]
        return nil unless resets_at

        reset_time = Time.parse(resets_at)
        now = Time.now
        minutes = window[:windowMinutes] || 10_080
        duration_seconds = minutes * 60.0
        time_until_reset = reset_time - now
        return nil unless time_until_reset.positive? && time_until_reset <= duration_seconds

        elapsed = clamp(duration_seconds - time_until_reset, 0, duration_seconds)
        expected_used_percent = clamp((elapsed / duration_seconds) * 100.0, 0, 100)
        actual_used_percent = clamp(window[:usedPercent].to_f, 0, 100)
        return nil if elapsed.zero? && actual_used_percent.positive?

        eta_seconds = nil
        will_last_to_reset = false
        if elapsed.positive? && actual_used_percent.positive?
          rate = actual_used_percent / elapsed
          remaining = [0, 100 - actual_used_percent].max
          candidate = remaining / rate
          if candidate >= time_until_reset
            will_last_to_reset = true
          elsif candidate.finite?
            eta_seconds = candidate
          end
        elsif elapsed.positive?
          will_last_to_reset = true
        end

        {
          deltaPercent: actual_used_percent - expected_used_percent,
          expectedUsedPercent: expected_used_percent,
          actualUsedPercent: actual_used_percent,
          etaSeconds: eta_seconds,
          willLastToReset: will_last_to_reset
        }
      end

      def duration_text(seconds)
        total_minutes = [1, (seconds.to_f / 60.0).ceil].max
        days = total_minutes / (24 * 60)
        hours = (total_minutes / 60) % 24
        minutes = total_minutes % 60
        return hours.positive? ? "#{days}d #{hours}h" : "#{days}d" if days.positive?
        return minutes.positive? ? "#{hours}h #{minutes}m" : "#{hours}h" if hours.positive?

        "#{minutes}m"
      end

      def clamp(value, min, max)
        [[value, min].max, max].min
      end
    end
  end
end
