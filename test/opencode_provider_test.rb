# frozen_string_literal: true

require_relative "test_helper"

class OpencodeProviderTest < Minitest::Test
  def test_usage_windows_map_rolling_weekly_monthly_to_primary_secondary_tertiary
    payload = {
      usage: {
        rolling: { status: "ok", percent: 2, resetsAt: "2026-09-14T09:04:57.771Z" },
        weekly: { status: "ok", percent: 0, resetsAt: "2026-09-21T00:00:00.771Z" },
        monthly: { status: "ok", percent: 0, resetsAt: "2026-10-14T04:00:14.771Z" }
      }
    }
    response = CodexBar::Core::Http::Response.new(status: 200, body: JSON.generate(payload), headers: {})

    result = nil
    with_temp_auth(key: "sk-test") do
      CodexBar::Core::Http.stub(:request, response) do
        result = CodexBar::Providers::Opencode.fetch(source: "auto")
      end
    end

    assert_nil result[:error]
    assert_equal "opencode", result[:provider]
    assert_equal "opencode-go", result[:source]

    usage = result[:usage]
    assert_equal 2.0, usage.dig(:primary, :usedPercent)
    assert_equal 300, usage.dig(:primary, :windowMinutes)
    assert_equal "2026-09-14T09:04:57Z", usage.dig(:primary, :resetsAt)
    assert_equal 0.0, usage.dig(:secondary, :usedPercent)
    assert_equal 10_080, usage.dig(:secondary, :windowMinutes)
    assert_equal 0.0, usage.dig(:tertiary, :usedPercent)
    assert_equal 43_200, usage.dig(:tertiary, :windowMinutes)
    assert_equal "OpenCode Go", usage.dig(:identity, :loginMethod)
  end

  def test_missing_windows_stay_absent_and_percent_is_clamped
    assert_nil CodexBar::Providers::Opencode.make_window(nil, 300)
    assert_nil CodexBar::Providers::Opencode.make_window({ status: "ok" }, 300)
    assert_equal 100.0, CodexBar::Providers::Opencode.make_window({ percent: 140, resetsAt: "2026-09-14T09:04:57Z" }, 300)[:usedPercent]
    assert_nil CodexBar::Providers::Opencode.make_window({ percent: 1, resetsAt: "1970-01-01T00:00:00Z" }, 300)[:resetsAt]
  end

  def test_resolve_api_key_prefers_opencode_go_then_opencode
    with_temp_auth(key: "sk-go") do
      assert_equal "sk-go", CodexBar::Providers::Opencode.resolve_api_key
    end
  end

  private

  def with_temp_auth(key:)
    Dir.mktmpdir("codexbar-opencode") do |dir|
      previous = ENV["CODEXBAR_OPENCODE_AUTH"]
      path = File.join(dir, "auth.json")
      File.write(path, JSON.generate(
        "opencode-go" => { type: "api", key: key },
        "opencode" => { type: "api", key: "sk-fallback" }
      ))
      ENV["CODEXBAR_OPENCODE_AUTH"] = path
      yield path
    ensure
      ENV["CODEXBAR_OPENCODE_AUTH"] = previous
    end
  end
end
