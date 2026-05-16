# frozen_string_literal: true

require_relative "test_helper"

class HistoryTest < Minitest::Test
  def test_history_updates_daily_usage_and_local_tokens
    Dir.mktmpdir("codexbar-state") do |dir|
      now = Time.now.utc
      config = build_config
      config[:runtime][:stateDir] = dir
      config = with_provider_state(config, "codex", enabled: true, visible: true)
      results = {
        "codex" => provider_result(
          provider: "codex",
          usage: usage_payload(
            provider: "codex",
            now: now,
            primary: window(used_percent: 41, window_minutes: 300, now: now, resets_in_minutes: 120)
          )
        )
      }
      snapshot = CodexBar::Runtime::State.build_snapshot(config, %w[codex], results, now)
      local_usage = {
        providers: {
          "codex" => {
            daily: [{ date: now.strftime("%Y-%m-%d"), totalTokens: 123, records: 2, cost: nil }]
          }
        }
      }

      history = CodexBar::Runtime::History.update(config, snapshot, local_usage, now: now)
      day = history.dig(:providers, "codex", :daily).last

      assert_equal 41, day[:latestPrimaryUsedPercent]
      assert_equal 123, day[:totalTokens]
      assert_equal 2, day[:records]
    end
  end
end
