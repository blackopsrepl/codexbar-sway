# frozen_string_literal: true

require "json"

module CodexBar
  module CLI
    module_function

    def run(argv = ARGV)
      command = argv.first&.start_with?("-") ? "usage" : (argv.shift || "usage")
      args = parse_args(argv)
      config_path = args[:config] || Core::Config.default_config_path

      case command
      when "bar"
        Runtime::Swaybar.run(config_path, args[:once])
        0
      when "config"
        run_config_command(args, config_path)
      when "display"
        run_display_command(args, config_path)
      when "daemon"
        Runtime::Daemon.run(config_path, once: args[:once])
        0
      when "open"
        run_open_command(args)
        0
      when "panel"
        Runtime::QuickShell.open(config_path, args[:provider])
        0
      when "providers"
        run_providers_command(args, config_path)
      when "refresh"
        snapshot = Runtime::Daemon.refresh(config_path)
        print_json_if_requested(snapshot, args)
        0
      when "ui"
        run_ui_command(args, config_path)
      when "usage"
        run_usage_command(args, config_path)
      when "waybar"
        run_waybar_command(args, config_path)
      else
        raise ArgumentError, "Unknown command: #{command}"
      end
    rescue StandardError => e
      warn e.message
      1
    end

    def parse_args(argv)
      args = {
        format: "text",
        once: false,
        pretty: false,
        provider: nil,
        positionals: []
      }

      index = 0
      while index < argv.length
        value = argv[index]
        case value
        when "--config"
          index += 1
          args[:config] = argv[index]
        when "--format"
          index += 1
          args[:format] = argv[index] == "json" ? "json" : "text"
        when "--pretty"
          args[:pretty] = true
        when "--once"
          args[:once] = true
        when "--provider"
          index += 1
          args[:provider] = argv[index]
        else
          args[:positionals] << value
        end
        index += 1
      end

      args
    end

    def run_usage_command(args, config_path)
      config = Core::Config.load_config(config_path)
      providers = args[:provider] ? parse_provider_list(args[:provider]) : Runtime::Usage.enabled_providers(config)
      results = Providers.fetch_providers(config, providers)

      if args[:format] == "json"
        payload = providers.filter_map { |provider| results[provider] }
        puts(args[:pretty] ? JSON.pretty_generate(payload) : JSON.generate(payload))
        return 0
      end

      sections = providers.filter_map do |provider|
        result = results[provider]
        next unless result

        if result[:error] || !result[:usage]
          "== #{provider} ==\nError: #{result[:error] || 'No data'}"
        else
          body = Core::Format.render_provider_text(
            provider,
            result[:usage],
            result[:credits],
            config.dig(:display, :showUsed),
            config.dig(:display, :resetStyle)
          )
          "== #{provider} (#{result[:source]}) ==\n#{body}"
        end
      end

      puts(sections.join("\n\n"))
      0
    end

    def run_config_command(args, config_path)
      subcommand = args[:positionals].first || "validate"
      if subcommand == "init"
        config = Core::Config.init_config(config_path)
        puts(JSON.pretty_generate(config))
        return 0
      end

      config = Core::Config.load_config(config_path)
      issues = Core::Config.validate_config(config)
      if args[:format] == "json"
        puts(args[:pretty] ? JSON.pretty_generate(issues) : JSON.generate(issues))
        return issues.any? { |issue| issue[:severity] == "error" } ? 1 : 0
      end

      if issues.empty?
        puts("Config valid.")
        return 0
      end

      issues.each do |issue|
        puts("#{issue[:severity].upcase}: #{issue[:field]} #{issue[:message]}")
      end
      issues.any? { |issue| issue[:severity] == "error" } ? 1 : 0
    end

    def run_providers_command(args, config_path)
      config = Core::Config.load_config(config_path)
      snapshot = Runtime::State.read_snapshot(config)
      subcommand = args[:positionals].first || "list"

      case subcommand
      when "list"
        rows = provider_rows(config, snapshot)
        print_provider_rows(rows, config, args)
      when "activate"
        provider = require_provider_argument(args[:positionals], 1)
        config = mutate_provider_config(config_path, config, provider, refresh: true) { |entry| entry[:enabled] = true }
        print_provider_change("Activated", provider, config, args)
      when "deactivate"
        provider = require_provider_argument(args[:positionals], 1)
        config = mutate_provider_config(config_path, config, provider, refresh: true) { |entry| entry[:enabled] = false }
        print_provider_change("Deactivated", provider, config, args)
      when "show"
        provider = require_provider_argument(args[:positionals], 1)
        config = mutate_provider_config(config_path, config, provider, refresh: false) { |entry| entry[:visible] = true }
        print_provider_change("Showing", provider, config, args)
      when "hide"
        provider = require_provider_argument(args[:positionals], 1)
        config = mutate_provider_config(config_path, config, provider, refresh: false) { |entry| entry[:visible] = false }
        print_provider_change("Hiding", provider, config, args)
      when "allow-auto"
        provider = require_provider_argument(args[:positionals], 1)
        config = mutate_provider_config(config_path, config, provider, refresh: false) { |entry| entry[:allowAutoSelect] = true }
        print_provider_change("Allowing auto-select for", provider, config, args)
      when "block-auto"
        provider = require_provider_argument(args[:positionals], 1)
        config = mutate_provider_config(config_path, config, provider, refresh: false) { |entry| entry[:allowAutoSelect] = false }
        print_provider_change("Blocking auto-select for", provider, config, args)
      when "pin"
        provider = require_provider_argument(args[:positionals], 1)
        ensure_provider_enabled!(config, provider)
        config = save_config(config_path, Core::Config.set_selected_provider(config, provider), refresh: false)
        print_provider_change("Pinned", provider, config, args)
      when "auto"
        config = save_config(config_path, Core::Config.set_highest_usage_mode(config), refresh: false)
        if args[:format] == "json"
          puts(args[:pretty] ? JSON.pretty_generate(config) : JSON.generate(config))
        else
          puts("Using highest-usage display mode.")
        end
      when "overview"
        run_providers_overview_command(args, config_path, config)
      else
        raise ArgumentError, "Unknown providers subcommand: #{subcommand}"
      end

      0
    end

    def run_providers_overview_command(args, config_path, config)
      action = args[:positionals][1]
      provider = require_provider_argument(args[:positionals], 2)

      case action
      when "add"
        config = mutate_provider_config(config_path, config, provider, refresh: false) { |entry| entry[:showInOverview] = true }
        print_provider_change("Added to overview", provider, config, args)
      when "remove"
        config = mutate_provider_config(config_path, config, provider, refresh: false) { |entry| entry[:showInOverview] = false }
        print_provider_change("Removed from overview", provider, config, args)
      else
        raise ArgumentError, "Unknown providers overview action: #{action || 'nil'}"
      end
    end

    def run_display_command(args, config_path)
      config = Core::Config.load_config(config_path)
      subcommand = args[:positionals].first || "status"

      case subcommand
      when "status"
        payload = {
          showHighestUsage: config.dig(:display, :showHighestUsage),
          selectedProvider: config.dig(:display, :selectedProvider),
          showUsed: config.dig(:display, :showUsed),
          displayMode: config.dig(:display, :displayMode)
        }
        if args[:format] == "json"
          puts(args[:pretty] ? JSON.pretty_generate(payload) : JSON.generate(payload))
        else
          puts("mode=#{payload[:showHighestUsage] ? 'auto' : 'pinned'} provider=#{payload[:selectedProvider]} show=#{payload[:showUsed] ? 'used' : 'remaining'} metric=#{payload[:displayMode]}")
        end
      when "used"
        updated = Core::Config.normalize_config(config)
        updated[:display][:showUsed] = true
        save_config(config_path, updated, refresh: false)
      when "remaining"
        updated = Core::Config.normalize_config(config)
        updated[:display][:showUsed] = false
        save_config(config_path, updated, refresh: false)
      when "mode"
        mode = args[:positionals][1].to_s
        raise ArgumentError, "Display mode must be one of both, percent, pace." unless %w[both percent pace].include?(mode)

        updated = Core::Config.normalize_config(config)
        updated[:display][:displayMode] = mode
        save_config(config_path, updated, refresh: false)
      else
        raise ArgumentError, "Unknown display subcommand: #{subcommand}"
      end

      0
    end

    def run_ui_command(args, config_path)
      subcommand = args[:positionals].first || "open"

      payload = case subcommand
                when "open"
                  Runtime::QuickShell.open(config_path, args[:provider])
                  Runtime::QuickShell.status(config_path)
                when "close"
                  Runtime::QuickShell.close(config_path)
                  Runtime::QuickShell.status(config_path)
                when "toggle"
                  Runtime::QuickShell.toggle(config_path, args[:provider])
                  Runtime::QuickShell.status(config_path)
                when "status"
                  Runtime::QuickShell.status(config_path)
                else
                  raise ArgumentError, "Unknown ui subcommand: #{subcommand}"
                end
      print_json_if_requested(payload, args)
      0
    end

    def run_open_command(args)
      subcommand = args[:positionals].first || "dashboard"

      case subcommand
      when "dashboard"
        provider = require_provider_argument(args[:positionals], 1)
        url = Core::Types::PROVIDER_METADATA.fetch(provider, {})[:dashboardUrl]
        raise ArgumentError, "No dashboard URL for #{provider}." unless url

        Core::Process.open_url(url)
      else
        raise ArgumentError, "Unknown open subcommand: #{subcommand}"
      end
    end

    def run_waybar_command(args, config_path)
      subcommand = args[:positionals].first || "render"

      case subcommand
      when "render"
        Runtime::Waybar.render(config_path)
      when "panel"
        Runtime::Waybar.open_panel(config_path, args[:provider])
      when "refresh"
        Runtime::Waybar.refresh(config_path)
      when "cycle-next"
        Runtime::Waybar.cycle(config_path, 1)
      when "cycle-prev"
        Runtime::Waybar.cycle(config_path, -1)
      else
        raise ArgumentError, "Unknown waybar subcommand: #{subcommand}"
      end

      0
    end

    def provider_rows(config, snapshot)
      config = Core::Config.normalize_config(config)
      enabled = Runtime::Usage.enabled_providers(config)
      results = Runtime::State.snapshot_results(snapshot)
      display_provider = if snapshot
                           snapshot[:displayProvider].to_s
                         else
                           Runtime::Usage.display_provider(config, enabled, results).to_s
                         end

      config[:providers].map do |provider|
        id = provider[:id]
        {
          id: id,
          label: Core::Types::PROVIDER_METADATA.fetch(id)[:label],
          enabled: provider[:enabled],
          visible: provider[:visible],
          showInOverview: provider[:showInOverview],
          allowAutoSelect: provider[:allowAutoSelect],
          selected: !config.dig(:display, :showHighestUsage) && config.dig(:display, :selectedProvider) == id,
          display: display_provider == id,
          summary: provider_result_summary(config, id, results[id] || results[id.to_sym])
        }
      end
    end

    def print_provider_rows(rows, config, args)
      if args[:format] == "json"
        puts(args[:pretty] ? JSON.pretty_generate(rows) : JSON.generate(rows))
        return
      end

      lines = []
      lines << "Display mode: #{config.dig(:display, :showHighestUsage) ? 'highest usage' : 'pinned'}"
      rows.sort_by { |row| [row[:enabled] ? 0 : 1, row[:visible] ? 0 : 1, row[:id]] }.each do |row|
        flags = []
        flags << (row[:enabled] ? "active" : "inactive")
        flags << (row[:visible] ? "visible" : "hidden")
        flags << (row[:showInOverview] ? "overview" : "no-overview")
        flags << (row[:allowAutoSelect] ? "auto" : "manual")
        flags << "display" if row[:display]
        flags << "pinned" if row[:selected]

        line = "#{row[:id].ljust(12)} #{flags.join(', ')}"
        line = "#{line}  #{row[:summary]}" if row[:summary]
        lines << line
      end
      puts(lines.join("\n"))
    end

    def provider_result_summary(config, provider, result)
      return nil unless result
      return "error: #{result[:error]}" if result[:error] && !result[:usage]
      return nil unless result[:usage]

      metric = Core::Metric.resolve_metric_window(
        provider,
        result[:usage],
        config.dig(:display, :metricPreferences, provider)
      )
      summary = Core::Format.compact_status_text(
        provider,
        result[:usage],
        config.dig(:display, :showUsed),
        config.dig(:display, :displayMode),
        metric
      )
      parts = [summary]
      parts << result[:source] if result[:source]
      parts.join(" | ")
    end

    def mutate_provider_config(config_path, config, provider, refresh:)
      updated = Core::Config.update_provider(config, provider) do |entry|
        yield(entry)
      end
      save_config(config_path, updated, refresh: refresh)
    end

    def save_config(config_path, config, refresh:)
      Core::Config.save_config(config, config_path)
      if refresh
        Runtime::Daemon.refresh(config_path, config: config)
      else
        Runtime::State.rebuild_snapshot(config)
        Runtime::Daemon.signal_waybar(config)
      end
      config
    end

    def ensure_provider_enabled!(config, provider)
      entry = Core::Config.provider_entry(config, provider)
      return if entry && entry[:enabled]

      raise ArgumentError, "Provider #{provider} is inactive. Activate it before pinning."
    end

    def print_provider_change(prefix, provider, config, args)
      if args[:format] == "json"
        payload = Core::Config.provider_entry(config, provider)
        puts(args[:pretty] ? JSON.pretty_generate(payload) : JSON.generate(payload))
      else
        puts("#{prefix} #{provider}.")
      end
    end

    def print_json_if_requested(payload, args)
      return unless args[:format] == "json"

      puts(args[:pretty] ? JSON.pretty_generate(payload) : JSON.generate(payload))
    end

    def require_provider_argument(positionals, index)
      provider = positionals[index]
      raise ArgumentError, "Provider argument is required." unless provider

      provider_id = provider.to_s.strip
      raise ArgumentError, "Unknown provider #{provider_id}." unless Core::Types.usage_provider?(provider_id)

      provider_id
    end

    def parse_provider_list(raw)
      if raw == "all"
        return Core::Config.normalize_config({})[:providers].map { |provider| provider[:id] }
      end

      providers = raw.split(",").map(&:strip).reject(&:empty?)
      raise ArgumentError, "No providers specified." if providers.empty?

      unknown = providers.reject { |provider| Core::Types.usage_provider?(provider) }
      raise ArgumentError, "Unknown providers: #{unknown.join(', ')}" unless unknown.empty?

      providers
    end
  end
end
