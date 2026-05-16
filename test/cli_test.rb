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
end
