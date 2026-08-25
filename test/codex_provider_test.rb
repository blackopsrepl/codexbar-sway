# frozen_string_literal: true

require_relative "test_helper"

class CodexProviderTest < Minitest::Test
  def test_rpc_uses_current_non_interactive_read_only_command
    assert_equal [
      "codex",
      "--sandbox", "read-only",
      "--ask-for-approval", "never",
      "app-server", "--stdio"
    ], CodexBar::Providers::Codex::RpcClient.command
  end

  def test_rate_limit_windows_are_classified_by_duration
    five_hour = { usedPercent: 12, windowDurationMins: 300 }
    weekly = { usedPercent: 34, windowDurationMins: 10_080 }
    response = {
      rateLimits: { primary: weekly, secondary: nil },
      rateLimitsByLimitId: {
        codex: { primary: weekly, secondary: five_hour }
      }
    }

    windows = CodexBar::Providers::Codex.rate_limit_windows(response)

    assert_same five_hour, windows[:primary]
    assert_same weekly, windows[:secondary]
  end

  def test_lone_weekly_window_does_not_become_the_five_hour_window
    weekly = { usedPercent: 7, windowDurationMins: 10_080 }

    windows = CodexBar::Providers::Codex.rate_limit_windows(
      rateLimits: { primary: weekly, secondary: nil }
    )

    assert_nil windows[:primary]
    assert_same weekly, windows[:secondary]
  end

  def test_credits_are_absent_when_account_has_no_credit_balance
    response = {
      rateLimits: {
        credits: { hasCredits: false, unlimited: false, balance: "0" }
      }
    }

    assert_nil CodexBar::Providers::Codex.make_credits(response)
  end

  def test_credits_use_the_codex_limit_bucket
    response = {
      rateLimits: { credits: { hasCredits: false, balance: "0" } },
      rateLimitsByLimitId: {
        codex: { credits: { hasCredits: true, balance: "2.5" } }
      }
    }

    credits = CodexBar::Providers::Codex.make_credits(response)

    assert_equal 2.5, credits[:remaining]
  end
end
