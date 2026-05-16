# frozen_string_literal: true

require_relative "test_helper"

class CliTest < Minitest::Test
  def test_config_dump_and_runtime_cadence_commands
    Dir.mktmpdir("codexbar-cli") do |dir|
      config_path = File.join(dir, "config.json")
      capture_stdout { CodexBar::CLI.run(["config", "init", "--config", config_path]) }

      output = capture_stdout do
        assert_equal 0, CodexBar::CLI.run(["runtime", "cadence", "manual", "--config", config_path, "--json"])
      end
      runtime = JSON.parse(output)

      assert_equal "manual", runtime["refreshMode"]

      output = capture_stdout do
        assert_equal 0, CodexBar::CLI.run(["config", "dump", "--config", config_path, "--json"])
      end
      config = JSON.parse(output)

      assert_equal 5, config["version"]
    end
  end

  def test_cache_clear_all_command
    Dir.mktmpdir("codexbar-cli") do |dir|
      config_path = File.join(dir, "config.json")
      config = build_config
      config[:runtime][:stateDir] = dir
      CodexBar::Core::Config.save_config(config, config_path)
      CodexBar::Runtime::State.write_status(config, generatedAt: Time.now.utc.iso8601)

      output = capture_stdout do
        assert_equal 0, CodexBar::CLI.run(["cache", "clear", "all", "--config", config_path, "--json"])
      end
      payload = JSON.parse(output)

      refute_empty payload["cleared"]
      refute File.exist?(CodexBar::Runtime::State.status_path(config))
    end
  end

  def test_provider_visibility_changes_apply_to_disabled_provider
    Dir.mktmpdir("codexbar-cli") do |dir|
      config_path = File.join(dir, "config.json")
      config = build_config
      config[:runtime][:stateDir] = dir
      config = with_provider_state(config, "claude", enabled: false, visible: true)
      CodexBar::Core::Config.save_config(config, config_path)

      capture_stdout do
        assert_equal 0, CodexBar::CLI.run(["providers", "hide", "claude", "--config", config_path, "--json"])
      end

      updated = CodexBar::Core::Config.load_config(config_path)
      claude = CodexBar::Core::Config.provider_entry(updated, "claude")
      assert_equal false, claude[:enabled]
      assert_equal false, claude[:visible]
    end
  end

  def test_provider_activation_does_not_block_on_synchronous_refresh
    Dir.mktmpdir("codexbar-cli") do |dir|
      config_path = File.join(dir, "config.json")
      config = build_config
      config[:runtime][:stateDir] = dir
      config = with_provider_state(config, "claude", enabled: false)
      CodexBar::Core::Config.save_config(config, config_path)

      CodexBar::Runtime::Daemon.stub(:refresh, ->(*) { raise "unexpected refresh" }) do
        capture_stdout do
          assert_equal 0, CodexBar::CLI.run(["providers", "activate", "claude", "--config", config_path, "--json"])
        end
      end

      updated = CodexBar::Core::Config.load_config(config_path)
      assert_equal true, CodexBar::Core::Config.provider_entry(updated, "claude")[:enabled]
    end
  end

  def test_status_refresh_rebuilds_snapshot_for_ui
    Dir.mktmpdir("codexbar-cli") do |dir|
      now = Time.now.utc
      config_path = File.join(dir, "config.json")
      config = build_config
      config[:runtime][:stateDir] = dir
      config = with_provider_state(config, "codex", enabled: true, visible: true, showInOverview: true)
      CodexBar::Core::Config.save_config(config, config_path)

      stale_status = {
        generatedAt: now.iso8601,
        providers: {
          "codex" => { provider: "codex", state: "unknown", description: "Status unavailable", updatedAt: now.iso8601 }
        }
      }
      result = provider_result(
        provider: "codex",
        usage: usage_payload(provider: "codex", now: now, primary: window(used_percent: 10, window_minutes: 300, now: now, resets_in_minutes: 60))
      )
      snapshot = CodexBar::Runtime::State.build_snapshot(config, %w[codex], { "codex" => result }, now, service_status: stale_status)
      CodexBar::Runtime::State.write_snapshot(config, snapshot)

      fresh_status = {
        generatedAt: now.iso8601,
        providers: {
          "codex" => { provider: "codex", state: "ok", description: "All Systems Operational", updatedAt: now.iso8601 }
        }
      }

      CodexBar::Runtime::Status.stub(:refresh, ->(loaded_config) {
        CodexBar::Runtime::State.write_status(loaded_config, fresh_status)
        fresh_status
      }) do
        CodexBar::Runtime::Daemon.stub(:signal_waybar, ->(*) {}) do
          capture_stdout do
            assert_equal 0, CodexBar::CLI.run(["status", "--config", config_path, "--json"])
          end
        end
      end

      rebuilt = CodexBar::Runtime::State.read_snapshot(config)
      codex = rebuilt.dig(:view, :providers).find { |entry| entry[:id] == "codex" }
      assert CodexBar::Runtime::State.result_for(rebuilt, "codex")[:usage]
      assert_equal "ok", codex[:serviceState]
      assert_equal "All Systems Operational", codex[:serviceStatusText]
    end
  end

  def test_cost_refresh_rebuilds_snapshot_for_ui
    Dir.mktmpdir("codexbar-cli") do |dir|
      now = Time.now.utc
      config_path = File.join(dir, "config.json")
      config = build_config
      config[:runtime][:stateDir] = dir
      config = with_provider_state(config, "gemini", enabled: true, visible: true, showInOverview: true)
      CodexBar::Core::Config.save_config(config, config_path)

      result = provider_result(
        provider: "gemini",
        usage: usage_payload(
          provider: "gemini",
          now: now,
          meters: [
            { key: "model:gemini-3-flash-preview", label: "gemini-3-flash-preview", usedPercent: 10.0, remainingPercent: 90.0 }
          ]
        )
      )
      snapshot = CodexBar::Runtime::State.build_snapshot(config, %w[gemini], { "gemini" => result }, now, local_usage: { providers: {} })
      CodexBar::Runtime::State.write_snapshot(config, snapshot)

      fresh_usage = {
        generatedAt: now.iso8601,
        scanDays: 30,
        providers: {
          "gemini" => {
            provider: "gemini",
            supported: true,
            records: 2,
            totalTokens: 1234,
            models: {},
            daily: []
          }
        }
      }

      CodexBar::Runtime::LocalUsage.stub(:refresh, ->(loaded_config) {
        CodexBar::Runtime::State.write_local_usage(loaded_config, fresh_usage)
        fresh_usage
      }) do
        CodexBar::Runtime::Daemon.stub(:signal_waybar, ->(*) {}) do
          capture_stdout do
            assert_equal 0, CodexBar::CLI.run(["cost", "--config", config_path, "--json"])
          end
        end
      end

      rebuilt = CodexBar::Runtime::State.read_snapshot(config)
      gemini = rebuilt.dig(:view, :providers).find { |entry| entry[:id] == "gemini" }
      assert_equal "1.2k tok · 2 records", gemini[:localUsageText]
    end
  end
end
