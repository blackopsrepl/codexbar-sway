# frozen_string_literal: true

require "json"

module CodexBar
  module Runtime
    module Swaybar
      module_function

      def run(config_path, once)
        config = Core::Config.load_config(config_path)
        enabled = Usage.enabled_providers(config)
        results = Usage.collect_usage(config, enabled)
        mutex = Mutex.new

        if once
          puts(JSON.generate(render_blocks(config, results, enabled)))
          return
        end

        $stdout.sync = true
        puts(JSON.generate(version: 1, click_events: true))
        puts("[")

        write_frame = lambda do
          blocks = mutex.synchronize { render_blocks(config, results, enabled) }
          puts("#{JSON.generate(blocks)},")
        end

        write_frame.call

        click_thread = Thread.new do
          listen_for_clicks do |event|
            case event[:button]
            when 2
              mutex.synchronize { results = Usage.collect_usage(config) }
              write_frame.call
            when 3, 4, 5
              next_provider = mutex.synchronize do
                Usage.cycle_provider(config, enabled, event[:button] == 4 ? -1 : 1)
              end
              next unless next_provider

              mutex.synchronize do
                config[:display][:selectedProvider] = next_provider
                config[:display][:showHighestUsage] = false
                Core::Config.save_config(config, config_path)
              end
              write_frame.call
            when 1
              action = mutex.synchronize { Menu.open_menu(config, results, enabled) }
              next unless action

              if action == "refresh"
                mutex.synchronize { results = Usage.collect_usage(config) }
                write_frame.call
                next
              end

              mutex.synchronize do
                config[:display][:selectedProvider] = action[:select]
                config[:display][:showHighestUsage] = false
                Core::Config.save_config(config, config_path)
              end
              write_frame.call
            end
          rescue StandardError => e
            warn "codexbar click handler error: #{e.message}"
          end
        end

        refresh_thread = Thread.new do
          loop do
            sleep(config.dig(:runtime, :refreshSeconds).to_i)
            mutex.synchronize { results = Usage.collect_usage(config) }
            write_frame.call
          rescue StandardError => e
            warn "codexbar refresh error: #{e.message}"
          end
        end

        [click_thread, refresh_thread].each(&:join)
      end

      def render_blocks(config, results, enabled)
        return [{ name: "codexbar", full_text: "codexbar idle", color: "#9be564" }] if enabled.empty?

        if config.dig(:display, :mergeIcons)
          selected = Usage.display_provider(config, enabled, results) || Usage.selected_provider(config, enabled)
          return [render_block(config, selected, results[selected])]
        end

        visible = Usage.visible_providers(config, enabled)
        providers = visible.empty? ? enabled : visible
        providers.map { |provider| render_block(config, provider, results[provider]) }
      end

      def render_block(config, provider, result)
        unless result && result[:usage]
          return {
            name: provider,
            full_text: "#{provider} err",
            color: "#ff6b6b",
            urgent: true
          }
        end

        metric = Core::Metric.resolve_metric_window(
          provider,
          result[:usage],
          config.dig(:display, :metricPreferences, provider)
        )

        {
          name: provider,
          full_text: Core::Format.compact_status_text(
            provider,
            result[:usage],
            config.dig(:display, :showUsed),
            config.dig(:display, :displayMode),
            metric
          ),
          color: result[:error] ? "#ff6b6b" : Core::Format.color_for_window(metric[:window]),
          urgent: !!result[:error]
        }
      end

      def listen_for_clicks
        buffer = +""

        loop do
          chunk = $stdin.readpartial(4096)
          buffer << chunk
          parsed = extract_next_object(buffer)
          while parsed
            buffer = parsed[:rest]
            yield(JSON.parse(parsed[:json], symbolize_names: true))
            parsed = extract_next_object(buffer)
          end
        end
      rescue EOFError
        nil
      end

      def extract_next_object(input)
        depth = 0
        in_string = false
        escape = false
        start = nil

        input.each_char.with_index do |char, index|
          if in_string
            if escape
              escape = false
            elsif char == "\\"
              escape = true
            elsif char == '"'
              in_string = false
            end
            next
          end

          if char == '"'
            in_string = true
          elsif char == "{"
            start = index if depth.zero?
            depth += 1
          elsif char == "}"
            depth -= 1
            if depth.zero? && start
              return {
                json: input[start..index],
                rest: input[(index + 1)..] || ""
              }
            end
          end
        end

        nil
      end
    end
  end
end
