# frozen_string_literal: true

require_relative "test_helper"

class RuntimeTest < Minitest::Test
  def test_build_snapshot_generates_view_counts_and_provider_badges
    now = Time.now.utc
    config = build_config
    config = with_provider_state(config, "codex", enabled: true, visible: true, showInOverview: true)
    config = with_provider_state(config, "claude", enabled: true, visible: false, showInOverview: false, allowAutoSelect: false)
    config = with_provider_state(config, "gemini", enabled: false, visible: true)
    config = CodexBar::Core::Config.set_selected_provider(config, "codex")

    results = {
      "codex" => provider_result(
        provider: "codex",
        usage: usage_payload(
          provider: "codex",
          now: now,
          primary: window(used_percent: 5, window_minutes: 300, now: now, resets_in_minutes: 240),
          secondary: window(used_percent: 24, window_minutes: 10_080, now: now, resets_in_minutes: 6_000)
        ),
        credits: { remaining: 3.0, updatedAt: now.iso8601 }
      ),
      "claude" => provider_result(
        provider: "claude",
        error: "Claude OAuth error: HTTP 403"
      )
    }

    snapshot = CodexBar::Runtime::State.build_snapshot(config, %w[codex claude], results, now)
    summary = snapshot.dig(:view, :summary)
    codex_view = snapshot.dig(:view, :providers).find { |entry| entry[:id] == "codex" }
    claude_view = snapshot.dig(:view, :providers).find { |entry| entry[:id] == "claude" }

    assert_equal %w[codex claude], snapshot[:enabledProviders]
    assert_equal %w[codex], snapshot[:visibleProviders]
    assert_equal %w[claude], snapshot[:hiddenProviders]
    assert_equal "codex", snapshot[:displayProvider]
    assert_equal 2, summary[:activeCount]
    assert_equal 1, summary[:visibleCount]
    assert_equal 1, summary[:hiddenCount]
    assert_includes codex_view[:badges], "display"
    assert_includes claude_view[:badges], "hidden"
    assert_equal "error", claude_view[:status]
  end

  def test_waybar_payload_contains_provider_metric_and_partial_classes
    now = Time.now.utc
    config = build_config
    config = with_provider_state(config, "codex", enabled: true, visible: true)
    config = with_provider_state(config, "claude", enabled: true, visible: false, allowAutoSelect: false)
    config = with_provider_state(config, "gemini", enabled: false, visible: true)
    config = CodexBar::Core::Config.set_selected_provider(config, "codex")

    results = {
      "codex" => provider_result(
        provider: "codex",
        usage: usage_payload(
          provider: "codex",
          now: now,
          primary: window(used_percent: 5, window_minutes: 300, now: now, resets_in_minutes: 240),
          secondary: window(used_percent: 24, window_minutes: 10_080, now: now, resets_in_minutes: 6_000)
        )
      ),
      "claude" => provider_result(
        provider: "claude",
        error: "Claude OAuth error: HTTP 403"
      )
    }

    snapshot = CodexBar::Runtime::State.build_snapshot(config, %w[codex claude], results, now)
    payload = CodexBar::Runtime::Waybar.payload(config, snapshot, now)

    assert_equal "󰚩 95%  76%  reserve", payload[:text]
    assert_includes payload[:class], "provider-codex"
    assert_includes payload[:class], "partial"
    assert_includes payload[:class], "pace-reserve"
    assert_includes payload[:tooltip], "Display: 󰚩 Codex"
  end

  def test_waybar_payload_reports_off_when_no_providers_are_enabled
    config = build_config
    payload = CodexBar::Runtime::Waybar.payload(config, nil, Time.now)

    assert_equal "󰚩 off", payload[:text]
    assert_includes payload[:class], "codexbar"
    assert_includes payload[:tooltip], "no providers enabled"
  end
end
