# frozen_string_literal: true

require_relative "test_helper"

class UsageTest < Minitest::Test
  def test_auto_display_ignores_hidden_provider_even_when_more_constrained
    now = Time.now.utc
    config = build_config
    config = with_provider_state(config, "codex", enabled: true, visible: true, allowAutoSelect: true)
    config = with_provider_state(config, "claude", enabled: true, visible: false, allowAutoSelect: true)

    results = {
      "codex" => provider_result(
        provider: "codex",
        usage: usage_payload(
          provider: "codex",
          now: now,
          primary: window(used_percent: 40, window_minutes: 300, now: now, resets_in_minutes: 180)
        )
      ),
      "claude" => provider_result(
        provider: "claude",
        usage: usage_payload(
          provider: "claude",
          now: now,
          primary: window(used_percent: 90, window_minutes: 300, now: now, resets_in_minutes: 180)
        )
      )
    }

    assert_equal "codex", CodexBar::Runtime::Usage.display_provider(config, %w[codex claude], results)
  end

  def test_pinned_hidden_provider_still_wins_when_auto_mode_is_disabled
    now = Time.now.utc
    config = build_config
    config = with_provider_state(config, "codex", enabled: true, visible: true)
    config = with_provider_state(config, "claude", enabled: true, visible: false)
    config = CodexBar::Core::Config.set_selected_provider(config, "claude")

    results = {
      "codex" => provider_result(
        provider: "codex",
        usage: usage_payload(
          provider: "codex",
          now: now,
          primary: window(used_percent: 40, window_minutes: 300, now: now, resets_in_minutes: 180)
        )
      ),
      "claude" => provider_result(
        provider: "claude",
        usage: usage_payload(
          provider: "claude",
          now: now,
          primary: window(used_percent: 90, window_minutes: 300, now: now, resets_in_minutes: 180)
        )
      )
    }

    assert_equal false, config.dig(:display, :showHighestUsage)
    assert_equal "claude", CodexBar::Runtime::Usage.display_provider(config, %w[codex claude], results)
  end

  def test_cycle_provider_prefers_visible_providers
    config = build_config
    config = with_provider_state(config, "codex", enabled: true, visible: true)
    config = with_provider_state(config, "claude", enabled: true, visible: true)
    config = with_provider_state(config, "gemini", enabled: true, visible: false)
    config = CodexBar::Core::Config.set_selected_provider(config, "codex")

    next_provider = CodexBar::Runtime::Usage.cycle_provider(config, %w[codex claude gemini], 1)

    assert_equal "claude", next_provider
  end

  def test_display_provider_ignores_external_status_payload
    now = Time.now.utc
    config = build_config
    config = with_provider_state(config, "codex", enabled: true, visible: true, allowAutoSelect: true)
    config = with_provider_state(config, "claude", enabled: true, visible: true, allowAutoSelect: true)
    results = {
      "codex" => provider_result(
        provider: "codex",
        usage: usage_payload(provider: "codex", now: now, primary: window(used_percent: 20, window_minutes: 300, now: now, resets_in_minutes: 180))
      ),
      "claude" => provider_result(
        provider: "claude",
        usage: usage_payload(provider: "claude", now: now, primary: window(used_percent: 80, window_minutes: 300, now: now, resets_in_minutes: 180))
      )
    }

    assert_equal "claude", CodexBar::Runtime::Usage.display_provider(config, %w[codex claude], results)
  end
end
