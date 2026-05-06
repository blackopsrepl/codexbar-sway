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

    assert_equal 4, config[:version]
    assert_equal %w[codex claude gemini], config[:providers].map { |entry| entry[:id] }
    assert_equal "codex", config.dig(:display, :selectedProvider)
    assert_equal "both", config.dig(:display, :displayMode)

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
end
