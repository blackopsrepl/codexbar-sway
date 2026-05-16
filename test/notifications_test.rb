# frozen_string_literal: true

require_relative "test_helper"

class NotificationsTest < Minitest::Test
  def test_notifications_fire_on_quota_warning_and_recovery_once
    Dir.mktmpdir("codexbar-state") do |dir|
      now = Time.now.utc
      config = build_config
      config[:runtime][:stateDir] = dir
      config[:notifications][:enabled] = true
      config = with_provider_state(config, "codex", enabled: true, visible: true)
      warning_snapshot = CodexBar::Runtime::State.build_snapshot(
        config,
        %w[codex],
        {
          "codex" => provider_result(
            provider: "codex",
            usage: usage_payload(provider: "codex", now: now, primary: window(used_percent: 90, window_minutes: 300, now: now, resets_in_minutes: 120))
          )
        },
        now
      )
      recovered_snapshot = CodexBar::Runtime::State.build_snapshot(
        config,
        %w[codex],
        {
          "codex" => provider_result(
            provider: "codex",
            usage: usage_payload(provider: "codex", now: now, primary: window(used_percent: 20, window_minutes: 300, now: now, resets_in_minutes: 120))
          )
        },
        now
      )
      messages = []

      CodexBar::Runtime::Notifications.stub(:notify, ->(_config, _title, message) { messages << message }) do
        CodexBar::Runtime::Notifications.process(config, nil, warning_snapshot, now: now)
        CodexBar::Runtime::Notifications.process(config, warning_snapshot, warning_snapshot, now: now)
        CodexBar::Runtime::Notifications.process(config, warning_snapshot, recovered_snapshot, now: now)
      end

      assert_equal 2, messages.length
      assert_includes messages.first, "critical"
      assert_includes messages.last, "recovered"
    end
  end
end
