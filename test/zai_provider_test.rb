# frozen_string_literal: true

require_relative "test_helper"

class ZaiProviderTest < Minitest::Test
  def test_quota_limits_map_session_weekly_tools_to_primary_secondary_tertiary
    result = fetch_with(quota_payload)

    assert_nil result[:error]
    assert_equal "zai", result[:provider]
    assert_equal "zai-coding-plan", result[:source]

    usage = result[:usage]
    assert_equal 16.0, usage.dig(:primary, :usedPercent)
    assert_equal 300, usage.dig(:primary, :windowMinutes)
    assert_equal "2026-05-03T14:47:11Z", usage.dig(:primary, :resetsAt)
    assert_equal 4.0, usage.dig(:secondary, :usedPercent)
    assert_equal 10_080, usage.dig(:secondary, :windowMinutes)
    assert_equal "2026-05-08T17:53:04Z", usage.dig(:secondary, :resetsAt)
    assert_equal 0.0, usage.dig(:tertiary, :usedPercent)
    assert_equal 43_200, usage.dig(:tertiary, :windowMinutes)
    assert_equal "GLM Coding Plan (lite)", usage.dig(:identity, :loginMethod)
    assert_empty result[:notes]
  end

  def test_credit_limit_type_is_accepted_as_a_quota_window
    payload = quota_payload(
      limits: [
        { type: "CREDIT_LIMIT", unit: 3, percentage: 25, nextResetTime: 1777819631597 },
        { type: "CREDIT_LIMIT", unit: 6, percentage: 10, nextResetTime: 1778262784969 }
      ]
    )

    result = fetch_with(payload)

    assert_nil result[:error]
    assert_equal 25.0, result.dig(:usage, :primary, :usedPercent)
    assert_equal 10.0, result.dig(:usage, :secondary, :usedPercent)
    assert_nil result.dig(:usage, :tertiary)
  end

  def test_make_window_clamps_and_rejects_implausible_reset_times
    assert_nil CodexBar::Providers::Zai.make_window(nil, 300)

    clamped = CodexBar::Providers::Zai.make_window({ percentage: 140, nextResetTime: 0 }, 300)
    assert_equal 100.0, clamped[:usedPercent]
    assert_nil clamped[:resetsAt]
  end

  def test_resolve_api_key_prefers_env_then_opencode_auth
    with_env("ZAI_API_KEY" => "sk-env") do
      with_temp_auth(key: "sk-auth") do
        assert_equal "sk-env", CodexBar::Providers::Zai.resolve_api_key
      end
    end

    with_env("ZAI_API_KEY" => nil, "GLM_API_KEY" => "sk-glm") do
      with_temp_auth(key: "sk-auth") do
        assert_equal "sk-glm", CodexBar::Providers::Zai.resolve_api_key
      end
    end

    with_env("ZAI_API_KEY" => nil, "GLM_API_KEY" => nil) do
      with_temp_auth(key: "sk-auth") do
        assert_equal "sk-auth", CodexBar::Providers::Zai.resolve_api_key
      end
    end
  end

  def test_missing_key_returns_error
    with_env("ZAI_API_KEY" => nil, "GLM_API_KEY" => nil) do
      Dir.mktmpdir("codexbar-zai") do |dir|
        path = File.join(dir, "auth.json")
        File.write(path, JSON.generate("opencode" => { type: "api", key: "sk-other" }))
        with_env("CODEXBAR_OPENCODE_AUTH" => path) do
          result = CodexBar::Providers::Zai.fetch({})

          assert_match(/API key not found/, result[:error])
          assert_nil result[:usage]
        end
      end
    end
  end

  def test_http_error_returns_error
    response = CodexBar::Core::Http::Response.new(status: 503, body: "", headers: {})

    result = nil
    with_temp_auth(key: "sk-auth") do
      CodexBar::Core::Http.stub(:request, response) do
        result = CodexBar::Providers::Zai.fetch({})
      end
    end

    assert_equal "Z.ai quota request failed with HTTP 503.", result[:error]
  end

  def test_missing_quota_windows_return_error
    result = fetch_with(quota_payload(limits: []))

    assert_match(/did not include usable token quota windows/, result[:error])
  end

  private

  def fetch_with(payload)
    response = CodexBar::Core::Http::Response.new(status: 200, body: JSON.generate(payload), headers: {})
    result = nil
    with_temp_auth(key: "sk-auth") do
      CodexBar::Core::Http.stub(:request, response) do
        result = CodexBar::Providers::Zai.fetch({})
      end
    end
    result
  end

  def quota_payload(limits: nil)
    {
      code: 200,
      data: {
        limits: limits || [
          { type: "TOKENS_LIMIT", unit: 3, percentage: 16, nextResetTime: 1777819631597 },
          { type: "TOKENS_LIMIT", unit: 6, percentage: 4, nextResetTime: 1778262784969 },
          { type: "TIME_LIMIT", unit: 5, percentage: 0, nextResetTime: 1780336384978 }
        ],
        level: "lite"
      }
    }
  end

  def with_temp_auth(key:)
    Dir.mktmpdir("codexbar-zai") do |dir|
      path = File.join(dir, "auth.json")
      File.write(path, JSON.generate("zai-coding-plan" => { type: "api", key: key }))
      with_env("CODEXBAR_OPENCODE_AUTH" => path) { yield path }
    end
  end

  def with_env(values)
    previous = values.transform_values { |_| nil }
    values.each_key { |name| previous[name] = ENV[name] }
    values.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    yield
  ensure
    previous.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end
end
