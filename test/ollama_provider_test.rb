# frozen_string_literal: true

require_relative "test_helper"

class OllamaProviderTest < Minitest::Test
  def test_monthly_plan_maps_to_the_primary_lane
    payload = {
      activity: { cost: "0.00000", period: { type: "last_4_weeks" }, models: [] },
      limits: {
        monthly: {
          usage: 0.125,
          models: [{ name: "gpt-oss:120b", request_count: 12 }]
        }
      }
    }

    result = fetch_with(payload)

    assert_nil result[:error]
    assert_equal "ollama", result[:provider]
    assert_equal "ollama-cloud", result[:source]

    usage = result[:usage]
    assert_equal 12.5, usage.dig(:primary, :usedPercent)
    assert_equal 43_200, usage.dig(:primary, :windowMinutes)
    assert_equal "mo", usage.dig(:primary, :shortLabel)
    assert_nil usage.dig(:primary, :resetsAt)
    assert_nil usage[:secondary]
    assert_equal "Ollama Cloud", usage.dig(:identity, :loginMethod)
    assert_empty result[:notes]
  end

  def test_legacy_session_and_weekly_plan_maps_to_primary_and_secondary
    payload = {
      limits: {
        session: { usage: 0.02, models: [] },
        weekly: { usage: 0.335, models: [] }
      }
    }

    result = fetch_with(payload)

    assert_nil result[:error]
    usage = result[:usage]
    assert_equal 2.0, usage.dig(:primary, :usedPercent)
    assert_equal 300, usage.dig(:primary, :windowMinutes)
    assert_equal "5h", usage.dig(:primary, :shortLabel)
    assert_equal 33.5, usage.dig(:secondary, :usedPercent)
    assert_equal 10_080, usage.dig(:secondary, :windowMinutes)
    assert_equal "W", usage.dig(:secondary, :shortLabel)
  end

  def test_usage_fraction_is_clamped_and_scale_is_normalized
    assert_equal 100.0, CodexBar::Providers::Ollama.usage_window({ usage: 1.4 }, 43_200, "Monthly", "mo")[:usedPercent]
    assert_equal 0.0, CodexBar::Providers::Ollama.usage_window({ usage: -0.5 }, 43_200, "Monthly", "mo")[:usedPercent]
    assert_nil CodexBar::Providers::Ollama.usage_window(nil, 43_200, "Monthly", "mo")
    assert_nil CodexBar::Providers::Ollama.usage_window({ usage: nil }, 43_200, "Monthly", "mo")
  end

  def test_resolve_api_key_prefers_env_then_opencode_auth
    with_env("OLLAMA_API_KEY" => "sk-env") do
      with_temp_auth(key: "sk-auth") do
        assert_equal "sk-env", CodexBar::Providers::Ollama.resolve_api_key
      end
    end

    with_env("OLLAMA_API_KEY" => nil) do
      with_temp_auth(key: "sk-auth") do
        assert_equal "sk-auth", CodexBar::Providers::Ollama.resolve_api_key
      end
    end
  end

  def test_missing_key_returns_error
    with_env("OLLAMA_API_KEY" => nil) do
      Dir.mktmpdir("codexbar-ollama") do |dir|
        path = File.join(dir, "auth.json")
        File.write(path, JSON.generate("opencode" => { type: "api", key: "sk-other" }))
        with_env("CODEXBAR_OPENCODE_AUTH" => path) do
          result = CodexBar::Providers::Ollama.fetch({})

          assert_match(/API key not found/, result[:error])
          assert_nil result[:usage]
        end
      end
    end
  end

  def test_http_error_returns_error
    response = CodexBar::Core::Http::Response.new(status: 401, body: "", headers: {})

    result = nil
    with_temp_auth(key: "sk-auth") do
      CodexBar::Core::Http.stub(:request, response) do
        result = CodexBar::Providers::Ollama.fetch({})
      end
    end

    assert_equal "Ollama Cloud usage request failed with HTTP 401.", result[:error]
  end

  def test_missing_allowance_windows_return_error
    result = fetch_with(limits: {})

    assert_match(/did not include a usable allowance window/, result[:error])
  end

  private

  def fetch_with(payload)
    response = CodexBar::Core::Http::Response.new(status: 200, body: JSON.generate(payload), headers: {})
    result = nil
    with_temp_auth(key: "sk-auth") do
      CodexBar::Core::Http.stub(:request, response) do
        result = CodexBar::Providers::Ollama.fetch({})
      end
    end
    result
  end

  def with_temp_auth(key:)
    Dir.mktmpdir("codexbar-ollama") do |dir|
      path = File.join(dir, "auth.json")
      File.write(path, JSON.generate("ollama-cloud" => { type: "api", key: key }))
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
