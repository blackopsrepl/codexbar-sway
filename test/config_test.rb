# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_normalize_config_keeps_supported_providers_and_sanitizes_fields
    config = CodexBar::Core::Config.normalize_config(
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
    config[:runtime][:quickShellShell] = "/tmp/codexbar-spec-missing-shell.qml"

    issues = CodexBar::Core::Config.validate_config(config)

    shell_issue = issues.find { |issue| issue[:field] == "runtime.quickShellShell" }
    refute_nil shell_issue
    assert_equal "warning", shell_issue[:severity]
  end

  def test_set_refresh_mode_normalizes_manual_and_interval
    config = build_config
    manual = CodexBar::Core::Config.set_refresh_mode(config, "manual")
    interval = CodexBar::Core::Config.set_refresh_mode(config, "interval", "60")

    assert_equal "manual", manual.dig(:runtime, :refreshMode)
    assert_equal 120, manual.dig(:runtime, :refreshSeconds)
    assert_equal "interval", interval.dig(:runtime, :refreshMode)
    assert_equal 60, interval.dig(:runtime, :refreshSeconds)
  end

  def test_local_usage_hermes_skip_providers_keeps_only_supported_provider_ids
    config = CodexBar::Core::Config.normalize_config(
      localUsage: { hermesSkipProviders: ["claude", "bogus", "claude", "ollama"] }
    )

    assert_equal %w[claude ollama], config.dig(:localUsage, :hermesSkipProviders)
    assert_equal [], CodexBar::Core::Config.default_config.dig(:localUsage, :hermesSkipProviders)
  end

  def test_save_config_writes_atomically_and_leaves_no_temp_file
    Dir.mktmpdir("codexbar-config") do |dir|
      path = File.join(dir, "config.json")
      config = CodexBar::Core::Config.default_config

      CodexBar::Core::Config.save_config(config, path)

      assert File.file?(path)
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_empty Dir.glob("#{path}.tmp.*"), "temp file left behind"
      assert_equal 5, JSON.parse(File.read(path))["version"]
    end
  end

  def test_save_config_never_exposes_a_torn_read_to_a_concurrent_reader
    Dir.mktmpdir("codexbar-config") do |dir|
      path = File.join(dir, "config.json")
      enabled = CodexBar::Core::Config.normalize_config(CodexBar::Core::Config.default_config)
      enabled[:providers].each { |provider| provider[:enabled] = true }
      CodexBar::Core::Config.save_config(enabled, path)

      torn = 0
      writer = Thread.new { 400.times { CodexBar::Core::Config.save_config(enabled, path) } }
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
end
