# frozen_string_literal: true

require_relative "test_helper"

class LocalUsageTest < Minitest::Test
  def test_scans_codex_last_token_usage
    with_temp_home do |home|
      path = File.join(home, ".codex", "sessions", "2026", "05", "16", "rollout.jsonl")
      write_jsonl(path, [
        {
          timestamp: Time.now.utc.iso8601,
          type: "event_msg",
          payload: {
            info: {
              last_token_usage: {
                input_tokens: 10,
                cached_input_tokens: 3,
                output_tokens: 5,
                reasoning_output_tokens: 2,
                total_tokens: 17
              }
            }
          }
        }
      ])

      summary = CodexBar::Runtime::LocalUsage.scan_codex(Time.now.utc - 86_400)

      assert_equal 1, summary[:records]
      assert_equal 17, summary[:totalTokens]
      assert_equal 3, summary[:cachedInputTokens]
    end
  end

  def test_scans_claude_project_usage_and_ignores_telemetry
    with_temp_home do |home|
      project_path = File.join(home, ".claude", "projects", "example", "session.jsonl")
      telemetry_path = File.join(home, ".claude", "telemetry", "events.json")
      write_jsonl(project_path, [
        {
          timestamp: Time.now.utc.iso8601,
          message: {
            usage: {
              input_tokens: 7,
              cache_read_input_tokens: 11,
              output_tokens: 13
            }
          }
        }
      ])
      FileUtils.mkdir_p(File.dirname(telemetry_path))
      File.write(telemetry_path, JSON.generate(event_data: { additional_metadata: { last_session_total_input_tokens: 999 } }))

      summary = CodexBar::Runtime::LocalUsage.scan_claude(Time.now.utc - 86_400)

      assert_equal 1, summary[:records]
      assert_equal 31, summary[:totalTokens]
      assert_equal 11, summary[:cachedInputTokens]
      assert_nil summary[:cost]
    end
  end

  def test_scans_gemini_chat_token_usage_by_model
    with_temp_home do |home|
      path = File.join(home, ".gemini", "tmp", "example", "chats", "session.jsonl")
      write_jsonl(path, [
        {
          sessionId: "session-1",
          kind: "main"
        },
        {
          timestamp: Time.now.utc.iso8601,
          type: "user",
          content: [{ text: "hello" }]
        },
        {
          timestamp: Time.now.utc.iso8601,
          type: "gemini",
          model: "gemini-3-flash-preview",
          tokens: {
            input: 10,
            output: 5,
            cached: 3,
            thoughts: 2,
            tool: 1,
            total: 18
          }
        },
        {
          timestamp: Time.now.utc.iso8601,
          type: "gemini",
          model: "gemini-2.5-pro",
          tokens: {
            input: 7,
            output: 11,
            cached: 0,
            thoughts: 13,
            tool: 17
          }
        }
      ])

      summary = CodexBar::Runtime::LocalUsage.scan_gemini(Time.now.utc - 86_400)

      assert_equal true, summary[:supported]
      assert_equal 2, summary[:records]
      assert_equal 66, summary[:totalTokens]
      assert_equal 3, summary[:cachedInputTokens]
      assert_equal 18, summary.dig(:models, "gemini-3-flash-preview", :totalTokens)
      assert_equal 48, summary.dig(:models, "gemini-2.5-pro", :totalTokens)
      assert_equal 17, summary.dig(:models, "gemini-2.5-pro", :toolTokens)
      assert_equal 2, summary[:daily].first[:records]
      assert_equal 66, summary[:daily].first[:totalTokens]
    end
  end

  def test_gemini_scan_ignores_old_and_malformed_records
    with_temp_home do |home|
      path = File.join(home, ".gemini", "tmp", "example", "chats", "session.jsonl")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(
        path,
        [
          "{not-json",
          JSON.generate(
            timestamp: (Time.now.utc - 172_800).iso8601,
            type: "gemini",
            model: "gemini-2.5-flash",
            tokens: { input: 100, output: 100, total: 200 }
          ),
          JSON.generate(
            timestamp: Time.now.utc.iso8601,
            type: "gemini",
            model: "gemini-2.5-flash",
            tokens: { input: 1, output: 2, total: 3 }
          )
        ].join("\n")
      )

      summary = CodexBar::Runtime::LocalUsage.scan_gemini(Time.now.utc - 86_400)

      assert_equal 1, summary[:records]
      assert_equal 3, summary[:totalTokens]
    end
  end
end
