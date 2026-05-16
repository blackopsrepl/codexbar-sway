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

  def test_history_retains_gemini_model_quota_and_local_usage
    Dir.mktmpdir("codexbar-state") do |dir|
      now = Time.now.utc
      date = now.strftime("%Y-%m-%d")
      config = build_config
      config[:runtime][:stateDir] = dir
      config = with_provider_state(config, "gemini", enabled: true, visible: true)
      results = {
        "gemini" => provider_result(
          provider: "gemini",
          usage: usage_payload(
            provider: "gemini",
            now: now,
            meters: [
              { key: "model:gemini-2.5-flash", label: "gemini-2.5-flash", modelId: "gemini-2.5-flash", usedPercent: 12.0, remainingPercent: 88.0 },
              { key: "model:gemini-2.5-pro", label: "gemini-2.5-pro", modelId: "gemini-2.5-pro", usedPercent: 34.0, remainingPercent: 66.0 }
            ]
          )
        )
      }
      snapshot = CodexBar::Runtime::State.build_snapshot(config, %w[gemini], results, now)
      local_usage = {
        providers: {
          "gemini" => {
            daily: [
              {
                date: date,
                totalTokens: 321,
                records: 3,
                models: {
                  "gemini-2.5-pro" => {
                    modelId: "gemini-2.5-pro",
                    totalTokens: 200,
                    records: 2,
                    inputTokens: 100,
                    outputTokens: 50,
                    cachedInputTokens: 25,
                    reasoningOutputTokens: 20,
                    toolTokens: 5
                  }
                }
              }
            ]
          }
        }
      }

      history = CodexBar::Runtime::History.update(config, snapshot, local_usage, now: now)
      day = history.dig(:providers, "gemini", :daily).last

      assert_equal 12.0, day.dig(:modelQuota, "gemini-2.5-flash", :latestUsedPercent)
      assert_equal 34.0, day.dig(:modelQuota, "gemini-2.5-pro", :latestUsedPercent)
      assert_equal 200, day.dig(:modelUsage, "gemini-2.5-pro", :totalTokens)
      assert_equal 5, day.dig(:modelUsage, "gemini-2.5-pro", :toolTokens)
    end
  end
end
