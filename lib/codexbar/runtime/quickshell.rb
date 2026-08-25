# frozen_string_literal: true

require "time"

module CodexBar
  module Runtime
    module QuickShell
      module_function

      def open(config_path, provider = nil)
        config = Core::Config.load_config(config_path)
        State.ensure_ui_state(config)
        state = State.read_ui_state(config)
        state[:open] = true
        state[:focusProvider] = resolve_provider(config, provider)
        state[:requestedAt] = Time.now.utc.iso8601
        State.write_ui_state(config, state)
        ensure_running(config_path, config)
      rescue StandardError => e
        notify_failure(config, e.message) if config
        raise
      end

      def close(config_path)
        config = Core::Config.load_config(config_path)
        State.ensure_ui_state(config)
        state = State.read_ui_state(config)
        state[:open] = false
        State.write_ui_state(config, state)
      end

      def toggle(config_path, provider = nil)
        config = Core::Config.load_config(config_path)
        State.ensure_ui_state(config)
        state = State.read_ui_state(config)
        return open(config_path, provider) unless state[:open]

        close(config_path)
      end

      def status(config_path)
        config = Core::Config.load_config(config_path)
        State.ensure_ui_state(config)
        pid = running_pid(config)
        {
          running: !pid.nil?,
          pid: pid,
          uiState: State.read_ui_state(config),
          shell: {
            command: config.dig(:runtime, :quickShellCommand),
            shell: config.dig(:runtime, :quickShellShell)
          }
        }
      end

      def ensure_running(config_path, config = nil)
        config ||= Core::Config.load_config(config_path)
        return running_pid(config) if running?(config)

        executable = resolve_quickshell_executable(config)
        shell = resolve_shell_path(config)
        env = {
          "CODEXBAR_BIN" => codexbar_executable,
          "CODEXBAR_CONFIG" => File.expand_path(config_path),
          "CODEXBAR_STATE_DIR" => State.state_dir(config),
          "QS_NO_RELOAD_POPUP" => "1",
          "QT_QPA_PLATFORM" => "wayland"
        }
        pid = Core::Process.spawn_detached(
          executable,
          ["--daemonize", "--no-duplicate", "--path", shell],
          env: env,
          cwd: File.dirname(shell)
        )
        sleep(0.5)
        waited_pid = wait_for_running_pid(config)
        waited_pid || pid
      end

      def running?(config)
        !running_pid(config).nil?
      end

      def running_pid(config)
        shell = resolve_shell_path(config)
        executable_name = File.basename(resolve_quickshell_executable(config))
        result = Core::Process.run_command("pgrep", ["-af", shell])
        return nil unless result[:exitCode].zero?

        result[:stdout].each_line do |entry|
          pid_text, command = entry.split(/\s+/, 2)
          next unless command&.include?(shell)

          pid = pid_text.to_i
          next unless process_executable_name(pid) == executable_name

          return pid
        end

        nil
      rescue StandardError
        nil
      end

      def process_executable_name(pid)
        File.basename(File.readlink("/proc/#{pid}/exe"))
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end

      def wait_for_running_pid(config, timeout_seconds: 2.0, interval_seconds: 0.05)
        deadline = Time.now + timeout_seconds
        loop do
          pid = running_pid(config)
          return pid if pid
          return nil if Time.now >= deadline

          sleep(interval_seconds)
        end
      end

      def resolve_provider(config, requested_provider)
        provider = requested_provider.to_s.strip
        return provider if Providers::FETCHERS.key?(provider)

        snapshot = State.read_snapshot(config)
        results = State.snapshot_results(snapshot)
        enabled = State.enabled_providers(snapshot)
        enabled = Usage.enabled_providers(config) if enabled.empty?
        Usage.display_provider(config, enabled, results) || Usage.selected_provider(config, enabled) || ""
      end

      def resolve_quickshell_executable(config)
        command = config.dig(:runtime, :quickShellCommand)
        executable = Core::Process.executable_path(command)
        return executable if executable

        raise "QuickShell executable not found for #{command.inspect}. Install QuickShell or set runtime.quickShellCommand."
      end

      def resolve_shell_path(config)
        shell = File.expand_path(config.dig(:runtime, :quickShellShell))
        return shell if File.file?(shell)

        raise "QuickShell shell file not found at #{shell}."
      end

      def codexbar_executable
        candidates = [
          ENV["CODEXBAR_BIN"],
          File.join(Dir.home, ".local", "bin", "codexbar"),
          File.expand_path("../../../bin/codexbar", __dir__),
          "codexbar"
        ].compact

        candidates.find { |candidate| candidate == "codexbar" || File.executable?(candidate) } || "codexbar"
      end

      def notify_failure(config, message)
        command = config.dig(:runtime, :notificationCommand).to_s.strip
        return if command.empty?

        Core::Process.spawn_detached(command, ["CodexBar", message])
      rescue StandardError
        nil
      end
    end
  end
end
