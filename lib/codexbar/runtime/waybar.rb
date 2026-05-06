# frozen_string_literal: true

require "json"
module CodexBar
  module Runtime
    module Waybar
      module_function

      def render(config_path, out: $stdout)
        config = Core::Config.load_config(config_path)
        snapshot = State.read_snapshot(config)
        out.puts(JSON.generate(payload(config, snapshot)))
      end

      def refresh(config_path)
        Daemon.refresh(config_path)
        nil
      end

      def open_panel(config_path, provider = nil)
        QuickShell.open(config_path, provider)
      end

      def cycle(config_path, direction)
        config = Core::Config.load_config(config_path)
        enabled = Usage.enabled_providers(config)
        next_provider = Usage.cycle_provider(config, enabled, direction)
        return nil unless next_provider

        updated = Core::Config.set_selected_provider(config, next_provider)
        Core::Config.save_config(updated, config_path)
        State.rebuild_snapshot(updated)
        Daemon.signal_waybar(updated)
        next_provider
      end

      def payload(config, snapshot, now = Time.now)
        snapshot_data = snapshot || State.build_snapshot(config, Usage.enabled_providers(config), {}, now.utc)
        view = Presenter.build_snapshot_view(config, snapshot_data, now)
        enabled = State.enabled_providers(snapshot)
        enabled = Usage.enabled_providers(config) if enabled.empty?
        chip = view[:chip] || {}

        if enabled.empty?
          return {
            text: "󰚩 off",
            tooltip: "CodexBar: no providers enabled",
            class: ["codexbar"]
          }
        end

        if snapshot.nil?
          classes = Array(chip[:classes])
          classes = ["codexbar", "loading"] if classes.empty?
          return {
            text: "󰚩 ...",
            tooltip: "CodexBar is waiting for cached data.\nMiddle click: refresh",
            class: classes
          }
        end
        {
          text: chip[:text] || "󰚩 ...",
          tooltip: Array(chip[:tooltipLines]).join("\n"),
          class: Array(chip[:classes]).uniq
        }
      end
    end
  end
end
