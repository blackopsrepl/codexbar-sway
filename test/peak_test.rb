# frozen_string_literal: true

require_relative "test_helper"

class PeakTest < Minitest::Test
  PEAK = CodexBar::Core::Peak

  def test_zai_peaks_weekdays_14_to_18_utc8
    # 2026-09-28 is a Monday. 06:00-10:00 UTC == 14:00-18:00 UTC+8.
    assert_equal "peak", PEAK.model_state("zai", nil, Time.utc(2026, 9, 28, 6, 0))[:state]
    assert_equal "peak", PEAK.model_state("zai", nil, Time.utc(2026, 9, 28, 9, 59))[:state]
    assert_equal "offpeak", PEAK.model_state("zai", nil, Time.utc(2026, 9, 28, 10, 0))[:state]
    assert_equal "offpeak", PEAK.model_state("zai", nil, Time.utc(2026, 9, 28, 5, 59))[:state]
    assert_equal "offpeak", PEAK.model_state("zai", nil, Time.utc(2026, 10, 3, 7, 0))[:state]
  end

  def test_ollama_peaks_weekdays_12_to_18_utc_only_for_deepseek_models
    assert_equal "offpeak", PEAK.model_state("ollama", "deepseek-v4.1-flash", Time.utc(2026, 9, 28, 11, 59))[:state]
    assert_equal "peak", PEAK.model_state("ollama", "deepseek-v4.1-flash", Time.utc(2026, 9, 28, 12, 0))[:state]
    assert_equal "offpeak", PEAK.model_state("ollama", "deepseek-v4.1-flash", Time.utc(2026, 9, 28, 18, 0))[:state]
    assert_nil PEAK.model_state("ollama", "gemma4", Time.utc(2026, 9, 28, 13, 0))
  end

  def test_opencode_peaks_only_for_deepseek_models
    assert_equal "peak", PEAK.model_state("opencode", "deepseek-v4-pro", Time.utc(2026, 9, 28, 2, 0))[:state]
    assert_equal "offpeak", PEAK.model_state("opencode", "deepseek-v4-pro", Time.utc(2026, 9, 28, 5, 0))[:state]
    assert_equal "peak", PEAK.model_state("opencode", "deepseek-v4-pro", Time.utc(2026, 9, 28, 7, 0))[:state]
    assert_nil PEAK.model_state("opencode", "kimi-k3", Time.utc(2026, 9, 28, 2, 0))
  end

  def test_providers_without_time_priced_models_have_no_state
    assert_nil PEAK.model_state("codex", "gpt-5.6-sol", Time.utc(2026, 9, 28, 2, 0))
    assert_nil PEAK.provider_state("codex", ["gpt-5.6-sol"], Time.utc(2026, 9, 28, 2, 0))
    assert_nil PEAK.model_state("claude", "claude-sonnet-4-5", Time.utc(2026, 9, 28, 2, 0))
  end

  def test_model_gated_provider_without_matching_model_has_no_state
    assert_nil PEAK.provider_state("opencode", ["kimi-k3", "glm-5.3"], Time.utc(2026, 9, 28, 2, 0))
    assert_equal "peak", PEAK.provider_state("opencode", ["kimi-k3", "deepseek-v4-pro"], Time.utc(2026, 9, 28, 2, 0))[:state]
  end

  def test_provider_wide_schedule_with_empty_models_still_reports
    state = PEAK.provider_state("zai", [], Time.utc(2026, 9, 28, 7, 0))

    assert_equal "peak", state[:state]
    assert_equal "Peak", state[:label]
    assert_equal [], state[:models]
  end

  def test_detail_text_is_attached
    state = PEAK.model_state("zai", nil, Time.utc(2026, 9, 28, 7, 0))

    assert_includes state[:detail], "UTC+8"
    assert_equal "Off-peak", PEAK.model_state("zai", nil, Time.utc(2026, 9, 28, 20, 0))[:label]
  end

  def test_presenter_marks_model_rows_and_provider_peak
    now = Time.utc(2026, 9, 28, 7, 0)
    models = {
      "deepseek-v4-pro" => { modelId: "deepseek-v4-pro", totalTokens: 100, records: 1 },
      "glm-5.3" => { modelId: "glm-5.3", totalTokens: 50, records: 1 }
    }

    rows = CodexBar::Runtime::Presenter.model_usage_rows("opencode", models, now)

    assert_equal "peak", rows.find { |row| row[:modelId] == "deepseek-v4-pro" }[:peak][:state]
    assert_nil rows.find { |row| row[:modelId] == "glm-5.3" }[:peak]
  end
end
