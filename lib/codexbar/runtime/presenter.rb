# frozen_string_literal: true

require "time"

module CodexBar
  module Runtime
    module Presenter
      TARGET_PROVIDERS = %w[codex claude gemini].freeze

      module_function

      def build_snapshot_view(config, snapshot, now = Time.now)
        results = snapshot[:results] || {}
        providers = supported_provider_order(config).map do |provider|
          build_provider_view(config, snapshot, provider, results[provider] || results[provider.to_sym], now)
        end

        {
          summary: build_summary_view(config, snapshot, providers, now),
          chip: build_chip_view(config, snapshot, results, providers, now),
          providers: providers
        }
      end

      def supported_provider_order(config)
        config.fetch(:providers, [])
          .map { |entry| entry[:id].to_s }
          .select { |provider| TARGET_PROVIDERS.include?(provider) }
      end

      def build_summary_view(config, snapshot, providers, now)
        display_provider = providers.find { |provider| provider[:display] }
        {
          activeCount: providers.count { |provider| provider[:enabled] },
          visibleCount: providers.count { |provider| provider[:enabled] && provider[:visible] },
          hiddenCount: providers.count { |provider| provider[:enabled] && !provider[:visible] },
          errorCount: providers.count { |provider| provider[:error].to_s.strip != "" },
          modeLabel: config.dig(:display, :showHighestUsage) ? "Highest usage" : "Pinned",
          showUsedLabel: config.dig(:display, :showUsed) ? "Used" : "Remaining",
          metricModeLabel: config.dig(:display, :displayMode).to_s,
          updatedText: summary_updated_text(snapshot, config, now),
          stale: stale_snapshot?(snapshot, config, now),
          displayProvider: display_provider && display_provider[:id],
          displayLabel: display_provider && display_provider[:label],
          displayText: display_provider && display_provider[:chipText]
        }
      end

      def build_chip_view(config, snapshot, results, providers, now)
        display_provider = snapshot[:displayProvider].to_s
        result = results[display_provider] || results[display_provider.to_sym]
        display_view = providers.find { |provider| provider[:id] == display_provider }
        classes = ["codexbar"]
        classes << "loading" if snapshot.nil?
        classes << "stale" if stale_snapshot?(snapshot, config, now)
        classes << display_provider unless display_provider.empty?
        classes << "provider-#{display_provider}" unless display_provider.empty?
        classes << (config.dig(:display, :showHighestUsage) ? "mode-auto" : "mode-pinned")
        classes.concat(result_classes(config, display_provider, result, results))

        {
          provider: display_provider,
          text: waybar_chip_text(config, display_provider, display_view, result),
          classes: classes.compact.uniq,
          tooltipLines: chip_tooltip_lines(config, snapshot, display_provider, results, providers, now)
        }
      end

      def build_provider_view(config, snapshot, provider, result, now)
        state = Usage.provider_state(config, provider) || {}
        usage = result && result[:usage]
        metric = Core::Metric.resolve_metric_window(
          provider,
          usage,
          config.dig(:display, :metricPreferences, provider)
        )
        dominant_metric = dominant_metric_view(config, provider, usage, metric, now)
        actual_metrics = metric_views(config, provider, usage, metric, now)
        updated_at = provider_updated_at(result, snapshot)
        stale = stale_snapshot?(snapshot, config, now)
        error = clean(result && result[:error])
        notes = Array(result && result[:notes]).filter_map { |note| clean(note) }
        identity = usage && usage[:identity] || {}
        status = provider_status(result, dominant_metric, stale)
        metadata = Core::Types::PROVIDER_METADATA.fetch(provider)
        chip_text = chip_text(config, provider, result)

        {
          id: provider,
          label: metadata[:label],
          shortLabel: metadata[:shortLabel],
          accent: metadata[:accent],
          icon: metadata[:icon] || "",
          dashboardUrl: metadata[:dashboardUrl],
          enabled: !!state[:enabled],
          visible: !!state[:visible],
          showInOverview: !!state[:showInOverview],
          allowAutoSelect: !!state[:allowAutoSelect],
          selected: !config.dig(:display, :showHighestUsage) && config.dig(:display, :selectedProvider) == provider,
          display: snapshot[:displayProvider].to_s == provider,
          inOverview: Array(snapshot[:overviewProviders]).map(&:to_s).include?(provider),
          autoEligible: Array(snapshot[:autoSelectableProviders]).map(&:to_s).include?(provider),
          chipText: chip_text,
          source: clean(result && result[:source]) || "cache",
          freshnessText: updated_at ? Core::Format.updated_string(updated_at.iso8601) : "Waiting for cached data",
          updatedAt: updated_at && updated_at.iso8601,
          stale: stale,
          status: status,
          dominantMetric: dominant_metric,
          metrics: actual_metrics,
          secondaryMetrics: actual_metrics.reject { |entry| dominant_metric && entry[:key] == dominant_metric[:key] },
          hero: hero_view(config, provider, usage, dominant_metric, now),
          detailCards: provider_detail_cards(config, provider, result, usage, dominant_metric, actual_metrics, now),
          creditsText: result && result[:credits] ? Core::Format.credits_string(result[:credits]) : nil,
          providerCostText: provider_cost_text(usage),
          spendLines: spend_lines(usage),
          identityText: identity_text(identity),
          accountEmail: clean(identity[:accountEmail]),
          loginMethod: clean(identity[:loginMethod]),
          error: error,
          notes: notes,
          incident: clean(result && result[:incident]),
          badges: provider_badges(config, snapshot, provider, status)
        }
      end

      def provider_badges(config, snapshot, provider, status)
        badges = []
        badges << "display" if snapshot[:displayProvider].to_s == provider
        badges << "pinned" if !config.dig(:display, :showHighestUsage) && config.dig(:display, :selectedProvider) == provider
        badges << "hidden" if Array(snapshot[:hiddenProviders]).map(&:to_s).include?(provider)
        badges << "overview" if Array(snapshot[:overviewProviders]).map(&:to_s).include?(provider)
        badges << "manual" unless Array(snapshot[:autoSelectableProviders]).map(&:to_s).include?(provider)
        badges << "stale" if status == "stale"
        badges
      end

      def provider_cost_text(usage)
        provider_cost = usage && usage[:providerCost]
        return nil unless provider_cost

        format(
          "%.2f / %.2f %s",
          provider_cost[:used].to_f,
          provider_cost[:limit].to_f,
          provider_cost[:currencyCode].to_s
        ).sub(/\.00\b/, "")
      end

      def spend_lines(usage)
        spend = usage && usage[:spend]
        return [] unless spend

        [
          Core::Format.spend_summary_line("Today", spend[:today]),
          Core::Format.spend_summary_line("7d", spend[:sevenDay]),
          Core::Format.spend_summary_line("Month", spend[:month])
        ].compact
      end

      def identity_text(identity)
        values = [clean(identity[:loginMethod]), clean(identity[:accountEmail])].compact
        values.empty? ? "No account metadata" : values.join(" / ")
      end

      def hero_view(config, provider, usage, dominant_metric, now)
        if dominant_metric
          {
            kind: "metric",
            icon: metric_icon(dominant_metric[:key]),
            title: dominant_metric[:label],
            value: dominant_metric[:summary],
            supporting: [
              pace_label(dominant_metric[:paceText]),
              dominant_metric[:resetText] ? "Reset #{dominant_metric[:resetText]}" : nil
            ].compact.join(" · "),
            detail: dominant_metric[:paceSummary],
            progressPercent: dominant_metric[:usedPercent].to_f,
            progressVisible: true
          }
        elsif usage && usage[:spend]
          month = usage[:spend][:month] || {}
          {
            kind: "history",
            icon: provider_icon(provider),
            title: "Month history",
            value: spend_hero_value(month),
            supporting: history_supporting_text(month, config, now),
            detail: history_detail_text(usage[:spend], config, now),
            progressPercent: provider_cost_percent(usage[:providerCost]),
            progressVisible: !usage[:providerCost].nil?
          }
        else
          {
            kind: "empty",
            icon: provider_icon(provider),
            title: "Status",
            value: "No quota data",
            supporting: nil,
            detail: nil,
            progressPercent: 0,
            progressVisible: false
          }
        end
      end

      def provider_detail_cards(config, provider, result, usage, dominant_metric, metrics, now)
        cards = metrics
          .reject { |entry| dominant_metric && entry[:key] == dominant_metric[:key] }
          .map { |entry| metric_card_view(config, entry, now) }
        cards.concat(spend_card_views(config, usage, now))
        provider_cost = usage && usage[:providerCost]
        if provider_cost
          cards << {
            key: "budget",
            icon: "",
            label: provider_cost[:period].to_s.empty? ? "Budget" : provider_cost[:period].to_s,
            value: provider_cost_text(usage),
            detail: "Budget window"
          }
        end

        if result && result[:credits]
          cards << {
            key: "credits",
            icon: "",
            label: "Credits",
            value: Core::Format.credits_string(result[:credits]),
            detail: "Remaining balance"
          }
        end

        cards
      end

      def metric_card_view(config, metric, now)
        {
          key: metric[:key],
          icon: metric_icon(metric[:key]),
          label: metric[:label],
          value: metric[:summary],
          detail: [
            pace_label(metric[:paceText]),
            metric[:resetText] ? "Reset #{metric[:resetText]}" : nil
          ].compact.join(" · ")
        }
      end

      def spend_card_views(config, usage, now)
        spend = usage && usage[:spend]
        return [] unless spend

        [
          ["today", "", "Today", spend[:today], false],
          ["seven-day", "", "7d", spend[:sevenDay], false],
          ["month", "", "Month", spend[:month], true]
        ].filter_map do |key, icon, label, summary, include_reset|
          next unless summary

          {
            key: key,
            icon: icon,
            label: label,
            value: spend_card_value(summary),
            detail: spend_card_detail(summary, config, now, include_reset: include_reset)
          }
        end
      end

      def spend_card_value(summary)
        return "#{summary[:requests].to_i} req" if summary[:requests].to_i.positive?
        return "#{format_tokens(summary[:tokens])} tok" if summary[:tokens].to_i.positive?

        "$#{Core::Format.money_string(summary[:cost].to_f)}"
      end

      def spend_card_detail(summary, config, now, include_reset:)
        parts = []
        parts << "#{format_tokens(summary[:tokens])} tok" if summary[:tokens].to_i.positive?
        parts << "$#{Core::Format.money_string(summary[:cost].to_f)}"
        if include_reset
          reset = Core::Format.compact_reset_text(summary, config.dig(:display, :resetStyle), now)
          parts << "Reset #{reset}" if reset
        end
        parts.join(" · ")
      end

      def spend_hero_value(summary)
        return "#{format_tokens(summary[:tokens])} tok" if summary[:tokens].to_i.positive?
        return "#{summary[:requests].to_i} req" if summary[:requests].to_i.positive?

        "$#{Core::Format.money_string(summary[:cost].to_f)}"
      end

      def history_supporting_text(summary, config, now)
        parts = []
        parts << "#{summary[:requests].to_i} req this month" if summary[:requests].to_i.positive?
        parts << "$#{Core::Format.money_string(summary[:cost].to_f)} billed"
        reset = Core::Format.compact_reset_text(summary, config.dig(:display, :resetStyle), now)
        parts << "Reset #{reset}" if reset
        parts.join(" · ")
      end

      def history_detail_text(spend, config, now)
        today = spend[:today] || {}
        seven_day = spend[:sevenDay] || {}
        month = spend[:month] || {}
        details = []
        details << "Today #{today[:requests].to_i} req" if today[:requests].to_i.positive?
        details << "7d #{seven_day[:requests].to_i} req" if seven_day[:requests].to_i.positive?
        details << "#{format_tokens(month[:tokens])} tokens this month" if month[:tokens].to_i.positive?
        details.join(" · ")
      end

      def provider_cost_percent(provider_cost)
        return 0 unless provider_cost && provider_cost[:limit].to_f.positive?

        (provider_cost[:used].to_f / provider_cost[:limit].to_f) * 100.0
      end

      def pace_label(value)
        clean(value)&.capitalize
      end

      def format_tokens(value)
        amount = value.to_i
        return amount.to_s if amount < 1000
        return format("%.1fk", amount / 1000.0).sub(".0k", "k") if amount < 1_000_000

        format("%.1fM", amount / 1_000_000.0).sub(".0M", "M")
      end

      def metric_icon(key)
        {
          "primary" => "",
          "secondary" => "",
          "tertiary" => "",
          "average" => ""
        }.fetch(key.to_s, "")
      end

      def provider_icon(provider)
        Core::Types::PROVIDER_METADATA.fetch(provider)[:icon] || ""
      end

      def build_metric_view(config, key, label, window, active_key, active_pace, now)
        return nil unless window

        pace = key == active_key ? active_pace : Core::Metric.usage_pace(window)
        {
          key: key,
          label: label,
          summary: Core::Format.usage_line(window, config.dig(:display, :showUsed)),
          remainingPercent: Core::Types.rate_window_remaining_percent(window),
          usedPercent: window[:usedPercent].to_f,
          resetText: Core::Format.compact_reset_text(window, config.dig(:display, :resetStyle), now),
          paceText: Core::Metric.pace_text(pace),
          paceSummary: Core::Metric.pace_summary_text(window),
          paceState: Core::Metric.pace_state(pace),
          severity: Core::Format.window_severity(window)
        }
      end

      def dominant_metric_view(config, provider, usage, resolved_metric, now)
        window = resolved_metric[:window]
        return nil unless window

        key, label = metric_identity(provider, usage, window, resolved_metric)
        build_metric_view(config, key, label, window, key, resolved_metric[:pace], now)
      end

      def metric_views(config, provider, usage, resolved_metric, now)
        return [] unless usage

        metadata = Core::Types::PROVIDER_METADATA.fetch(provider)
        active_key, = metric_identity(provider, usage, resolved_metric[:window], resolved_metric)
        [
          ["primary", metadata[:sessionLabel] || "Primary", usage[:primary]],
          ["secondary", metadata[:weeklyLabel] || "Secondary", usage[:secondary]],
          ["tertiary", metadata[:tertiaryLabel] || "Tertiary", usage[:tertiary]]
        ].filter_map do |key, label, window|
          build_metric_view(config, key, label, window, active_key, resolved_metric[:pace], now)
        end
      end

      def metric_identity(provider, usage, window, resolved_metric)
        metadata = Core::Types::PROVIDER_METADATA.fetch(provider)
        return ["average", "Average"] if resolved_metric[:effective] == "average" && !same_window?(usage && usage[:primary], window) && !same_window?(usage && usage[:secondary], window)
        return ["primary", metadata[:sessionLabel] || "Primary"] if same_window?(usage && usage[:primary], window)
        return ["secondary", metadata[:weeklyLabel] || "Secondary"] if same_window?(usage && usage[:secondary], window)
        return ["tertiary", metadata[:tertiaryLabel] || "Tertiary"] if same_window?(usage && usage[:tertiary], window)

        ["primary", metadata[:sessionLabel] || "Primary"]
      end

      def same_window?(left, right)
        !left.nil? && !right.nil? && left == right
      end

      def chip_text(config, provider, result)
        return "CB ..." if provider.to_s.empty?
        return "#{short_label(provider)} err" if result && result[:error] && !result[:usage]
        return "#{short_label(provider)} ..." unless result && result[:usage]

        metric = Core::Metric.resolve_metric_window(
          provider,
          result[:usage],
          config.dig(:display, :metricPreferences, provider)
        )
        Core::Format.compact_status_text(
          provider,
          result[:usage],
          config.dig(:display, :showUsed),
          config.dig(:display, :displayMode),
          metric
        )
      end

      def waybar_chip_text(config, provider, provider_view, result)
        return "󰚩 ..." if provider.to_s.empty?
        return "#{provider_icon(provider)} err" if result && result[:error] && !result[:usage]
        return "#{provider_icon(provider)} ..." unless provider_view

        primary = provider_view[:metrics].find { |metric| metric[:key] == "primary" } || provider_view[:dominantMetric]
        secondary = provider_view[:metrics].find { |metric| metric[:key] == "secondary" }

        if primary
          parts = [provider_view[:icon], compact_metric_percent(config, primary)]
          parts << waybar_metric_segment(config, secondary) if secondary
          parts << pace_chip_segment(primary)
          return parts.compact.join(" ")
        end

        compact = provider_view[:chipText].to_s.sub(/^#{Regexp.escape(provider_view[:shortLabel].to_s)}\s+/, "")
        compact = provider_view[:chipText].to_s if compact.empty?
        [provider_view[:icon], compact].compact.join(" ").strip
      end

      def chip_tooltip_lines(config, snapshot, display_provider, results, providers, now)
        lines = []
        lines << "Display: #{display_provider.to_s.empty? ? 'none' : "#{provider_icon(display_provider)} #{provider_label(display_provider)}"}"
        hidden = Array(snapshot[:hiddenProviders]).map(&:to_s)
        lines << "Hidden: #{hidden.join(', ')}" unless hidden.empty?
        lines << summary_updated_text(snapshot, config, now)
        lines << ""

        Array(snapshot[:overviewProviders]).map(&:to_s).each do |provider|
          provider_view = providers.find { |entry| entry[:id] == provider }
          result = results[provider] || results[provider.to_sym]
          prefix = provider == display_provider ? "*" : " "
          lines << "#{prefix} #{tooltip_provider_line(config, provider, provider_view, result)}"
        end

        lines.compact
      end

      def tooltip_provider_line(config, provider, provider_view, result)
        return "#{provider_icon(provider)} #{provider_label(provider)}: err" if result && result[:error] && !result[:usage]
        return "#{provider_icon(provider)} #{provider_label(provider)}: ..." unless provider_view

        metrics = []
        primary = provider_view[:metrics].find { |metric| metric[:key] == "primary" } || provider_view[:dominantMetric]
        secondary = provider_view[:metrics].find { |metric| metric[:key] == "secondary" }
        tertiary = provider_view[:metrics].find { |metric| metric[:key] == "tertiary" }

        metrics << metric_tooltip_text(config, primary) if primary
        metrics << metric_tooltip_text(config, secondary) if secondary
        metrics << metric_tooltip_text(config, tertiary) if tertiary && provider_view[:metrics].length > 2

        summary = if metrics.empty?
                    compact = provider_view[:chipText].to_s.sub(/^#{Regexp.escape(provider_view[:shortLabel].to_s)}\s+/, "")
                    detail_icon = provider_view.dig(:hero, :icon)
                    detail_icon = nil if detail_icon == provider_view[:icon]
                    [detail_icon, compact].compact.join(" ").strip
                  else
                    metrics.join(" · ")
                  end

        "#{provider_view[:icon]} #{provider_view[:label]}: #{summary}"
      end

      def metric_tooltip_text(config, metric)
        "#{metric_icon(metric[:key])} #{metric[:label]} #{metric_summary_text(config, metric)}"
      end

      def waybar_metric_segment(config, metric)
        "#{metric_icon(metric[:key])} #{compact_metric_percent(config, metric)}"
      end

      def pace_chip_segment(metric)
        state = metric && metric[:paceText].to_s
        return nil if state.empty?

        compact = case state
                  when "on pace"
                    "pace"
                  else
                    state
                  end
        " #{compact}"
      end

      def compact_metric_percent(config, metric)
        metric_summary_percent(config, metric) || metric[:summary].to_s
      end

      def metric_summary_text(config, metric)
        percent = metric_summary_percent(config, metric)
        return metric[:summary].to_s unless percent

        show_used = config.dig(:display, :showUsed)
        "#{percent} #{show_used ? 'used' : 'left'}"
      end

      def metric_summary_percent(config, metric)
        value = if config.dig(:display, :showUsed)
                  metric[:usedPercent]
                else
                  metric[:remainingPercent]
                end
        return nil if value.nil?

        "#{value.to_f.round}%"
      end

      def result_classes(config, display_provider, display_result, results)
        errors = results.values.count { |result| result && result[:error] }
        classes = []
        classes << "error" if display_result && display_result[:error] && !display_result[:usage]
        classes << "partial" if errors.positive? && (display_result.nil? || !(display_result[:error] && !display_result[:usage]))
        return classes unless display_provider && display_result && display_result[:usage]

        metric = Core::Metric.resolve_metric_window(
          display_provider,
          display_result[:usage],
          config.dig(:display, :metricPreferences, display_provider)
        )
        severity = Core::Format.window_severity(metric[:window])
        pace_state = Core::Metric.pace_state(metric[:pace])
        classes << severity if severity
        classes << "pace-#{pace_state}" if pace_state
        classes
      end

      def provider_status(result, dominant_metric, stale)
        return "loading" unless result
        return "error" if result[:error] && !result[:usage]
        return "incident" if clean(result[:incident])
        return "stale" if stale

        dominant_metric && dominant_metric[:severity] || "healthy"
      end

      def summary_updated_text(snapshot, config, now)
        return "Waiting for cached data" unless snapshot[:generatedAt]

        text = Core::Format.updated_string(snapshot[:generatedAt])
        stale_snapshot?(snapshot, config, now) ? "#{text} · stale" : text
      end

      def stale_snapshot?(snapshot, config, now)
        generated_at = parse_time(snapshot && snapshot[:generatedAt])
        return true unless generated_at

        generated_at < (now - [config.dig(:runtime, :refreshSeconds).to_i * 2, 60].max)
      end

      def provider_updated_at(result, snapshot)
        timestamp = result&.dig(:usage, :updatedAt) ||
          result&.dig(:credits, :updatedAt) ||
          result&.dig(:providerCost, :updatedAt) ||
          result&.dig(:spend, :month, :updatedAt) ||
          snapshot[:generatedAt]
        parse_time(timestamp)
      end

      def parse_time(value)
        return nil if value.to_s.strip.empty?

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def clean(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def short_label(provider)
        Core::Types::PROVIDER_METADATA.fetch(provider)[:shortLabel]
      end

      def provider_label(provider)
        Core::Types::PROVIDER_METADATA.fetch(provider)[:label]
      end
    end
  end
end
