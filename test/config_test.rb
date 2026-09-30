# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_normalize_config_keeps_supported_providers_and_sanitizes_fields
    config = TokenMaxx::Core::Config.normalize_config(
      version: 999,
      providers: [
        { id: "claude", enabled: "true", visible: false, showInOverview: false, allowAutoSelect: false, source: "oauth" },
        { id: "unknown", enabled: true }
      ],
      display: {
        selectedProvider: "unknown",
        displayMode: "invalid"
      }
    )

    assert_equal 5, config[:version]
    assert_equal %w[codex claude gemini opencode zai ollama], config[:providers].map { |entry| entry[:id] }
    assert_equal "codex", config.dig(:display, :selectedProvider)
    assert_equal "both", config.dig(:display, :displayMode)
    assert_equal "interval", config.dig(:runtime, :refreshMode)
    assert_equal true, config.dig(:status, :enabled)
    assert_equal false, config.dig(:notifications, :enabled)
    assert_equal 30, config.dig(:history, :retentionDays)

    claude = config[:providers].find { |entry| entry[:id] == "claude" }
    assert_equal true, claude[:enabled]
    assert_equal false, claude[:visible]
    assert_equal false, claude[:showInOverview]
    assert_equal false, claude[:allowAutoSelect]
    assert_equal "oauth", claude[:source]
  end

  def test_validate_config_warns_when_quickshell_shell_is_missing
    config = build_config
    config[:runtime][:quickShellShell] = "/tmp/tokenmaxx-spec-missing-shell.qml"

    issues = TokenMaxx::Core::Config.validate_config(config)

    shell_issue = issues.find { |issue| issue[:field] == "runtime.quickShellShell" }
    refute_nil shell_issue
    assert_equal "warning", shell_issue[:severity]
  end

  def test_set_refresh_mode_normalizes_manual_and_interval
    config = build_config
    manual = TokenMaxx::Core::Config.set_refresh_mode(config, "manual")
    interval = TokenMaxx::Core::Config.set_refresh_mode(config, "interval", "60")

    assert_equal "manual", manual.dig(:runtime, :refreshMode)
    assert_equal 120, manual.dig(:runtime, :refreshSeconds)
    assert_equal "interval", interval.dig(:runtime, :refreshMode)
    assert_equal 60, interval.dig(:runtime, :refreshSeconds)
  end

  def test_local_usage_hermes_skip_providers_keeps_only_supported_provider_ids
    config = TokenMaxx::Core::Config.normalize_config(
      localUsage: { hermesSkipProviders: ["claude", "bogus", "claude", "ollama"] }
    )

    assert_equal %w[claude ollama], config.dig(:localUsage, :hermesSkipProviders)
    assert_equal [], TokenMaxx::Core::Config.default_config.dig(:localUsage, :hermesSkipProviders)
  end

  def test_save_config_writes_atomically_and_leaves_no_temp_file
    Dir.mktmpdir("tokenmaxx-config") do |dir|
      path = File.join(dir, "config.json")
      config = TokenMaxx::Core::Config.default_config

      TokenMaxx::Core::Config.save_config(config, path)

      assert File.file?(path)
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_empty Dir.glob("#{path}.tmp.*"), "temp file left behind"
      assert_equal 5, JSON.parse(File.read(path))["version"]
    end
  end

  def test_save_config_never_exposes_a_torn_read_to_a_concurrent_reader
    Dir.mktmpdir("tokenmaxx-config") do |dir|
      path = File.join(dir, "config.json")
      enabled = TokenMaxx::Core::Config.normalize_config(TokenMaxx::Core::Config.default_config)
      enabled[:providers].each { |provider| provider[:enabled] = true }
      TokenMaxx::Core::Config.save_config(enabled, path)

      torn = 0
      writer = Thread.new { 400.times { TokenMaxx::Core::Config.save_config(enabled, path) } }
      reader = Thread.new do
        4000.times do
          raw = File.read(path)
          torn += 1 unless raw.end_with?("}\n") && JSON.parse(raw).is_a?(Hash)
        rescue JSON::ParserError, Errno::ENOENT
          torn += 1
        end
      end
      writer.join
      reader.join

      assert_equal 0, torn, "concurrent readers observed a torn config write"
    end
  end

  def test_load_config_imports_legacy_default_config_once
    Dir.mktmpdir("tokenmaxx-legacy-migrate") do |home|
      old_home = ENV["HOME"]
      ENV["HOME"] = home
      begin
        legacy_dir = File.join(home, ".codexbar")
        FileUtils.mkdir_p(legacy_dir)
        TokenMaxx::Core::Config.save_config(
          TokenMaxx::Core::Config.default_config,
          File.join(legacy_dir, "config.json")
        )
        new_path = File.join(home, ".config", "tokenmaxx", "config.json")
        refute File.exist?(new_path), "precondition: new config absent"

        config = TokenMaxx::Core::Config.load_config

        assert File.file?(new_path), "legacy default config was not imported"
        assert_equal 5, JSON.parse(File.read(new_path))["version"]
        assert_equal config[:version], JSON.parse(File.read(new_path))["version"]
        assert File.file?(File.join(legacy_dir, "config.json")), "legacy config must be left in place"

        # no_fallback: after the one-time import the old path is dead weight.
        File.delete(File.join(legacy_dir, "config.json"))
        again = TokenMaxx::Core::Config.load_config
        assert_equal config[:providers].map { |p| p[:id] }, again[:providers].map { |p| p[:id] }
      ensure
        ENV["HOME"] = old_home
      end
    end
  end

  def test_load_config_with_explicit_path_never_imports_legacy_config
    Dir.mktmpdir("tokenmaxx-legacy-hermetic") do |home|
      old_home = ENV["HOME"]
      ENV["HOME"] = home
      begin
        legacy_dir = File.join(home, ".codexbar")
        FileUtils.mkdir_p(legacy_dir)
        TokenMaxx::Core::Config.save_config(
          TokenMaxx::Core::Config.default_config,
          File.join(legacy_dir, "config.json")
        )

        Dir.mktmpdir("tokenmaxx-explicit") do |dir|
          path = File.join(dir, "config.json")
          config = TokenMaxx::Core::Config.load_config(path)

          assert_equal 5, config[:version]
          refute File.exist?(path), "explicit config path must not be created by a legacy import"
          refute File.exist?(File.join(home, ".config", "tokenmaxx")), "explicit --config runs must stay hermetic"
        end
      ensure
        ENV["HOME"] = old_home
      end
    end
  end

  def test_normalize_runtime_remaps_only_the_legacy_default_state_dir
    legacy = File.join(Dir.home, ".local", "state", "codexbar")
    config = TokenMaxx::Core::Config.normalize_config(runtime: { stateDir: legacy })

    assert_equal File.join(Dir.home, ".local", "state", "tokenmaxx"), config.dig(:runtime, :stateDir)

    custom = File.join(Dir.home, "quota-state-somewhere-else")
    kept = TokenMaxx::Core::Config.normalize_config(runtime: { stateDir: custom })

    assert_equal custom, kept.dig(:runtime, :stateDir)
  end
end
