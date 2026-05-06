# frozen_string_literal: true

module CodexBar
  module Runtime
    module Daemon
      module_function

      def run(config_path, once: false)
        config = Core::Config.load_config(config_path)
        return refresh(config_path, config: config) if once

        lock = State.acquire_daemon_lock(config)
        raise "codexbar daemon already running for #{State.state_dir(config)}." unless lock

        refresh(config_path, config: config)

        loop do
          sleep(config.dig(:runtime, :refreshSeconds).to_i)
          refresh(config_path, config: config)
        rescue StandardError => e
          warn "codexbar daemon refresh error: #{e.message}"
        end
      ensure
        lock&.close
      end

      def refresh(config_path, config: nil)
        config ||= Core::Config.load_config(config_path)
        snapshot = nil

        State.with_refresh_lock(config) do
          enabled = Usage.enabled_providers(config)
          results = Usage.collect_usage(config, enabled)
          snapshot = State.build_snapshot(config, enabled, results)
          State.write_snapshot(config, snapshot)
        end

        signal_waybar(config)
        snapshot
      end

      def signal_waybar(config)
        signal = config.dig(:runtime, :waybarSignal).to_i
        return if signal <= 0

        Core::Process.run_command("pkill", ["-RTMIN+#{signal}", "waybar"])
      rescue StandardError
        nil
      end
    end
  end
end
