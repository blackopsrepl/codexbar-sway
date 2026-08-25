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
          refreshModeLabel: config.dig(:runtime, :refreshMode).to_s == "manual" ? "Manual refresh" : "#{config.dig(:runtime, :refreshSeconds).to_i}s refresh",
          statusLabel: config.dig(:status, :enabled) ? "Status on" : "Status off",
          notificationsLabel: config.dig(:notifications, :enabled) ? "Notify on" : "Notify off",
          privacyLabel: config.dig(:privacy, :hidePersonalInfo) ? "Privacy on" : "Privacy off",
          localUsageText: local_usage_summary(snapshot[:localUsage]),
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
        classes << "manual-refresh" if config.dig(:runtime, :refreshMode) == "manual"
        classes << "notifications-on" if config.dig(:notifications, :enabled)
        classes << "privacy-on" if config.dig(:privacy, :hidePersonalInfo)
        classes << "service-#{display_view[:serviceState]}" if display_view && %w[degraded outage].include?(display_view[:serviceState].to_s)
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
        service_status = auxiliary_provider(snapshot[:serviceStatus], provider)
        local_usage = auxiliary_provider(snapshot[:localUsage], provider)
        storage = auxiliary_provider(snapshot[:storage], provider)
        history = auxiliary_provider(snapshot[:history], provider)
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
        status = provider_status(result, dominant_metric, actual_metrics, stale, service_status)
        metadata = Core::Types::PROVIDER_METADATA.fetch(provider)
        chip_text = chip_text(config, provider, result)
        incident = clean(result && result[:incident]) || service_incident(service_status)

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
          quotaSummaryText: quota_summary_text(config, provider, actual_metrics),
          secondaryMetrics: actual_metrics.reject { |entry| dominant_metric && entry[:key] == dominant_metric[:key] },
          hero: hero_view(config, provider, usage, dominant_metric, now),
          detailCards: provider_detail_cards(config, provider, result, usage, dominant_metric, actual_metrics, now, service_status, local_usage, storage, history),
          creditsText: result && result[:credits] ? Core::Format.credits_string(result[:credits]) : nil,
          providerCostText: provider_cost_text(usage),
          spendLines: spend_lines(usage),
          identityText: identity_text(identity, config.dig(:privacy, :hidePersonalInfo)),
          accountEmail: clean(identity[:accountEmail]),
          loginMethod: clean(identity[:loginMethod]),
          serviceState: clean(service_status[:state]) || "unknown",
          serviceStatusText: Core::Format.service_status_text(service_status),
          serviceStatusUpdatedAt: clean(service_status[:updatedAt]),
          localUsageText: local_usage_text(local_usage),
          localUsageModels: model_usage_rows(local_usage && local_usage[:models]),
          storageText: storage && storage[:totalBytes] ? Core::Format.bytes_string(storage[:totalBytes]) : nil,
          historySummary: provider_history_summary(history),
          historyDays: provider_history_days(history),
          error: error,
          notes: notes,
          incident: incident,
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

      def identity_text(identity, hide_personal_info = false)
        email = hide_personal_info ? Core::Format.redact_email(identity[:accountEmail]) : clean(identity[:accountEmail])
        values = [clean(identity[:loginMethod]), email].compact
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

      def provider_detail_cards(config, provider, result, usage, dominant_metric, metrics, now, service_status = nil, local_usage = nil, storage = nil, history = nil)
        cards = metrics
          .reject { |entry| dominant_metric && entry[:key] == dominant_metric[:key] }
          .map { |entry| metric_card_view(config, entry, now) }
        cards << service_status_card(service_status) if service_status && !service_status.empty?
        cards.concat(spend_card_views(config, usage, now))
        local_card = local_usage_card(local_usage)
        cards << local_card if local_card
        history_card = history_card(history)
        cards << history_card if history_card
        storage_card = storage_card(storage)
        cards << storage_card if storage_card
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

      def service_status_card(service_status)
        {
          key: "service-status",
          icon: service_status[:state].to_s == "ok" ? "" : "󰀨",
          label: "Service",
          value: service_status[:state].to_s.empty? ? "unknown" : service_status[:state].to_s,
          detail: Core::Format.service_status_text(service_status)
        }
      end

      def local_usage_card(local_usage)
        text = Core::Format.token_summary_line(local_usage)
        return nil unless text

        {
          key: "local-usage",
          icon: "",
          label: "Local usage",
          value: text,
          detail: "Exact local logs"
        }
      end

      def local_usage_text(local_usage)
        return nil unless local_usage && !local_usage.empty?
        return "Local usage unsupported" if local_usage[:supported] == false

        Core::Format.token_summary_line(local_usage) || "No local token summary"
      end

      def model_usage_rows(models)
        return [] unless models.is_a?(Hash)

        models.values
          .select { |entry| entry.is_a?(Hash) && entry[:totalTokens].to_i.positive? }
          .sort_by { |entry| [-entry[:totalTokens].to_i, entry[:modelId].to_s] }
          .map do |entry|
            {
              modelId: entry[:modelId].to_s,
              label: entry[:modelId].to_s,
              tokensText: "#{format_tokens(entry[:totalTokens])} tok",
              recordsText: entry[:records].to_i.positive? ? "#{entry[:records]} records" : nil,
              detail: model_usage_detail(entry)
            }
          end
      end

      def model_usage_detail(entry)
        parts = []
        parts << "#{format_tokens(entry[:inputTokens])} in" if entry[:inputTokens].to_i.positive?
        parts << "#{format_tokens(entry[:cachedInputTokens])} cached" if entry[:cachedInputTokens].to_i.positive?
        parts << "#{format_tokens(entry[:outputTokens])} out" if entry[:outputTokens].to_i.positive?
        parts << "#{format_tokens(entry[:reasoningOutputTokens])} thought" if entry[:reasoningOutputTokens].to_i.positive?
        parts << "#{format_tokens(entry[:toolTokens])} tool" if entry[:toolTokens].to_i.positive?
        parts.join(" / ")
      end

      def history_card(history)
        latest = Array(history && history[:daily]).last
        return nil unless latest

        values = [
          latest[:latestPrimaryUsedPercent].to_f.positive? ? "P #{latest[:latestPrimaryUsedPercent].round}%" : nil,
          latest[:latestSecondaryUsedPercent].to_f.positive? ? "W #{latest[:latestSecondaryUsedPercent].round}%" : nil,
          latest[:totalTokens].to_i.positive? ? "#{format_tokens(latest[:totalTokens])} tok" : nil
        ].compact
        return nil if values.empty?

        {
          key: "history",
          icon: "",
          label: Core::Format.date_label(latest[:date]),
          value: values.join(" / "),
          detail: "Latest retained day"
        }
      end

      def provider_history_summary(history)
        days = provider_history_days(history)
        return "No retained history" if days.empty?

        token_total = days.sum { |entry| entry[:totalTokens].to_i }
        quota_peak = days.map { |entry| entry[:barPercent].to_f }.max.to_f
        parts = ["#{days.length} retained days"]
        parts << "#{format_tokens(token_total)} local tokens" if token_total.positive?
        parts << "#{quota_peak.round}% peak quota" if quota_peak.positive?
        parts.join(" / ")
      end

      def provider_history_days(history)
        Array(history && history[:daily]).last(14).map do |entry|
          primary = entry[:latestPrimaryUsedPercent].to_f
          secondary = entry[:latestSecondaryUsedPercent].to_f
          tertiary = entry[:latestTertiaryUsedPercent].to_f
          quota = [primary, secondary, tertiary].max
          token_text = entry[:totalTokens].to_i.positive? ? "#{format_tokens(entry[:totalTokens])} tok" : nil
          records_text = entry[:records].to_i.positive? ? "#{entry[:records]} records" : nil
          cost_text = entry[:cost] ? "$#{Core::Format.money_string(entry[:cost].to_f)}" : nil
          model_text = history_day_model_text(entry)
          detail = [token_text, records_text, cost_text, model_text].compact.join(" / ")
          {
            date: entry[:date].to_s,
            label: Core::Format.date_label(entry[:date]),
            primaryPercent: primary,
            secondaryPercent: secondary,
            tertiaryPercent: tertiary,
            barPercent: quota,
            quotaText: quota.positive? ? "#{quota.round}% quota" : "No quota sample",
            totalTokens: entry[:totalTokens].to_i,
            records: entry[:records].to_i,
            cost: entry[:cost],
            detail: detail.empty? ? "No local token summary" : detail,
            modelDetails: history_day_model_details(entry)
          }
        end
      end

      def history_day_model_text(entry)
        models = history_day_model_details(entry)
        return nil if models.empty?

        "#{models.length} models"
      end

      def history_day_model_details(entry)
        usage = entry[:modelUsage].is_a?(Hash) ? entry[:modelUsage] : {}
        quota = entry[:modelQuota].is_a?(Hash) ? entry[:modelQuota] : {}
        keys = (usage.keys + quota.keys).uniq
        keys.filter_map do |model_id|
          usage_entry = usage[model_id] || {}
          quota_entry = quota[model_id] || {}
          tokens = usage_entry[:totalTokens].to_i
          quota_percent = quota_entry[:latestUsedPercent].to_f
          next if tokens.zero? && quota_percent.zero?

          parts = []
          parts << "#{format_tokens(tokens)} tok" if tokens.positive?
          parts << "#{quota_percent.round}% quota" if quota_percent.positive?
          {
            modelId: model_id.to_s,
            label: quota_entry[:label].to_s.empty? ? model_id.to_s : quota_entry[:label].to_s,
            detail: parts.join(" / ")
          }
        end.sort_by { |entry| entry[:label] }
      end

      def storage_card(storage)
        return nil unless storage && storage[:totalBytes].to_i.positive?

        {
          key: "storage",
          icon: "",
          label: "Storage",
          value: Core::Format.bytes_string(storage[:totalBytes]),
          detail: Array(storage[:paths]).select { |entry| entry[:exists] }.map { |entry| File.basename(entry[:path].to_s) }.join(", ")
        }
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
        }.fetch(key.to_s, "")
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
          shortLabel: clean(window[:shortLabel]),
          modelId: clean(window[:modelId]),
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

        if Array(usage[:meters]).any?
          active_key, = metric_identity(provider, usage, resolved_metric[:window], resolved_metric)
          return usage[:meters].filter_map do |meter|
            build_metric_view(config, meter[:key], meter[:label], meter, active_key, resolved_metric[:pace], now)
          end
        end

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

      def quota_summary_text(config, provider, metrics)
        return nil unless provider == "codex"

        entries = metrics.sort_by do |entry|
          { "primary" => 0, "secondary" => 1, "tertiary" => 2 }.fetch(entry[:key].to_s, 3)
        end
        parts = entries.map do |entry|
          label = entry[:key] == "primary" ? "5h" : (entry[:key] == "secondary" ? "W" : entry[:label])
          "#{label} #{compact_metric_percent(config, entry)}"
        end
        parts.empty? ? nil : parts.join(" / ")
      end

      def metric_identity(provider, usage, window, resolved_metric)
        metadata = Core::Types::PROVIDER_METADATA.fetch(provider)
        Array(usage && usage[:meters]).each do |meter|
          return [meter[:key], meter[:label]] if same_window?(meter, window)
        end
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

        if provider_view[:metrics].any? { |metric| metric[:key].to_s.start_with?("model:") }
          metric = provider_view[:dominantMetric] || provider_view[:metrics].first
          parts = [provider_view[:icon], metric[:shortLabel] || metric[:label], compact_metric_percent(config, metric)]
          return parts.compact.join(" ")
        end

        primary = provider_view[:metrics].find { |metric| metric[:key] == "primary" }
        secondary = provider_view[:metrics].find { |metric| metric[:key] == "secondary" }

        if primary
          parts = [provider_view[:icon], compact_metric_percent(config, primary)]
          parts << waybar_metric_segment(config, secondary) if secondary
          return parts.compact.join(" ")
        end
        return [provider_view[:icon], waybar_metric_segment(config, secondary)].join(" ") if secondary

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

        model_metrics = provider_view[:metrics].select { |metric| metric[:key].to_s.start_with?("model:") }
        metrics = if model_metrics.any?
                    model_metrics.map { |metric| metric_tooltip_text(config, metric) }
                  else
                    primary = provider_view[:metrics].find { |metric| metric[:key] == "primary" }
                    secondary = provider_view[:metrics].find { |metric| metric[:key] == "secondary" }
                    tertiary = provider_view[:metrics].find { |metric| metric[:key] == "tertiary" }
                    named_metrics = [primary, secondary, tertiary && provider_view[:metrics].length > 2 ? tertiary : nil].compact.sort_by do |metric|
                      { "primary" => 0, "secondary" => 1, "tertiary" => 2 }.fetch(metric[:key].to_s, 3)
                    end.map { |metric| metric_tooltip_text(config, metric) }
                    named_metrics = [metric_tooltip_text(config, provider_view[:dominantMetric])] if named_metrics.empty? && provider_view[:dominantMetric]
                    named_metrics
                  end

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

      def aggregate_model_meter_severity(severities)
        levels = Array(severities).compact
        return nil if levels.empty?
        return "critical" if levels.all? { |level| level == "critical" }
        return "warning" if levels.any? { |level| %w[critical warning].include?(level) }

        "healthy"
      end

      def provider_quota_status(dominant_metric, metrics)
        model_metrics = Array(metrics).select { |metric| metric[:key].to_s.start_with?("model:") }
        return aggregate_model_meter_severity(model_metrics.map { |metric| metric[:severity] }) unless model_metrics.empty?

        dominant_metric && dominant_metric[:severity] || "healthy"
      end

      def result_quota_status(usage, resolved_window)
        meters = Array(usage && usage[:meters])
        unless meters.empty?
          return aggregate_model_meter_severity(meters.map { |meter| Core::Format.window_severity(meter) })
        end

        Core::Format.window_severity(resolved_window)
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
        severity = result_quota_status(display_result[:usage], metric[:window])
        classes << severity if severity
        classes
      end

      def provider_status(result, dominant_metric, metrics, stale, service_status = nil)
        return "loading" unless result
        return "error" if result[:error] && !result[:usage]
        return "incident" if %w[degraded outage].include?(service_status && service_status[:state].to_s)
        return "incident" if clean(result[:incident])
        return "stale" if stale

        provider_quota_status(dominant_metric, metrics)
      end

      def auxiliary_provider(payload, provider)
        providers = payload && payload[:providers]
        return {} unless providers

        providers[provider] || providers[provider.to_sym] || {}
      end

      def service_incident(service_status)
        return nil unless service_status
        return nil unless %w[degraded outage].include?(service_status[:state].to_s)

        clean(service_status[:incident]) || clean(service_status[:description])
      end

      def local_usage_summary(local_usage)
        providers = local_usage && local_usage[:providers]
        return "Local usage pending" unless providers

        total = providers.values.sum { |entry| entry[:totalTokens].to_i }
        return "Local usage ready" if total.zero?

        "#{format_tokens(total)} local tokens"
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
