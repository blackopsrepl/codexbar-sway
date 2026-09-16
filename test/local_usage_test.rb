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

  def test_scans_codex_attributes_tokens_to_session_model
    with_temp_home do |home|
      path = File.join(home, ".codex", "sessions", "2026", "05", "16", "rollout.jsonl")
      write_jsonl(path, [
        {
          timestamp: Time.now.utc.iso8601,
          type: "turn_context",
          payload: { model: "gpt-5.6-sol" }
        },
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

      assert_equal ["gpt-5.6-sol"], summary[:models].keys
      assert_equal 17, summary.dig(:models, "gpt-5.6-sol", :totalTokens)
      assert_equal 17, summary.dig(:daily, 0, :models, "gpt-5.6-sol", :totalTokens)
    end
  end

  def test_scans_claude_attributes_tokens_to_message_model
    with_temp_home do |home|
      path = File.join(home, ".claude", "projects", "example", "session.jsonl")
      write_jsonl(path, [
        {
          timestamp: Time.now.utc.iso8601,
          message: {
            model: "claude-sonnet-4-5",
            usage: {
              input_tokens: 7,
              cache_read_input_tokens: 11,
              output_tokens: 13
            }
          }
        }
      ])

      summary = CodexBar::Runtime::LocalUsage.scan_claude(Time.now.utc - 86_400)

      assert_equal ["claude-sonnet-4-5"], summary[:models].keys
      assert_equal 31, summary.dig(:models, "claude-sonnet-4-5", :totalTokens)
      assert_equal 31, summary.dig(:daily, 0, :models, "claude-sonnet-4-5", :totalTokens)
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

  def test_summarizes_opencode_messages_by_model_and_activity_day
    rows = [
      {
        date: "2026-09-13",
        model_id: "deepseek-v4-pro",
        records: 1,
        input_tokens: 100,
        cached_input_tokens: 7,
        output_tokens: 50,
        reasoning_output_tokens: 10,
        total_tokens: 167,
        cost: 0.056
      },
      {
        date: "2026-09-14",
        model_id: "gemini-3-flash-preview",
        records: 1,
        input_tokens: 200,
        cached_input_tokens: 0,
        output_tokens: 40,
        reasoning_output_tokens: 0,
        total_tokens: 240,
        cost: 0.044
      }
    ]

    summary = CodexBar::Runtime::LocalUsage.summarize_opencode_messages(rows)

    assert_equal true, summary[:supported]
    assert_equal 2, summary[:records]
    assert_equal 407, summary[:totalTokens]
    assert_equal 7, summary[:cachedInputTokens]
    assert_in_delta 0.1, summary[:cost], 0.0001
    assert_equal 167, summary.dig(:models, "deepseek-v4-pro", :totalTokens)
    assert_equal 240, summary.dig(:models, "gemini-3-flash-preview", :totalTokens)
    assert_equal 2, summary[:daily].length
    assert_equal "2026-09-13", summary[:daily][0][:date]
    assert_equal 167, summary[:daily][0][:totalTokens]
    assert_equal "2026-09-14", summary[:daily][1][:date]
    assert_equal 240, summary[:daily][1][:totalTokens]
    assert_equal 240, summary.dig(:daily, 1, :models, "gemini-3-flash-preview", :totalTokens)
  end

  def test_opencode_message_query_uses_recent_sessions_and_message_activity
    calls = []
    result = lambda do |_command, args, **_options|
      calls << args
      if args.last.include?("SELECT id FROM session")
        { exitCode: 0, stdout: JSON.generate([{ id: "session-1" }]) }
      else
        { exitCode: 0, stdout: "[]" }
      end
    end

    CodexBar::Core::Process.stub(:run_command, result) do
      CodexBar::Runtime::LocalUsage.opencode_messages("/tmp/opencode.db", Time.utc(2026, 9, 14))
    end

    assert_equal 2, calls.length
    assert_includes calls.first.last, "time_updated >="
    assert_includes calls.last.last, "FROM message"
    assert_includes calls.last.last, "time_created >="
    assert_includes calls.last.last, "json_extract(data, '$.modelID')"
  end

  def test_scan_opencode_returns_empty_summary_without_database
    Dir.mktmpdir("codexbar-opencode") do |dir|
      previous = ENV["CODEXBAR_OPENCODE_DB"]
      ENV["CODEXBAR_OPENCODE_DB"] = File.join(dir, "missing.db")

      summary = CodexBar::Runtime::LocalUsage.scan_opencode(Time.now.utc - 86_400)

      assert_equal true, summary[:supported]
      assert_equal 0, summary[:records]
    ensure
      ENV["CODEXBAR_OPENCODE_DB"] = previous
    end
  end

  def test_opencode_db_path_uses_custom_home
    with_temp_home do |home|
      previous = ENV.delete("CODEXBAR_OPENCODE_DB")

      assert_equal File.join(home, ".local", "share", "opencode", "opencode.db"), CodexBar::Runtime::LocalUsage.opencode_db_path
    ensure
      ENV["CODEXBAR_OPENCODE_DB"] = previous
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
  def test_opencode_message_query_scopes_providers
    calls = []
    result = lambda do |_command, args, **_options|
      calls << args
      if args.last.include?("SELECT id FROM session")
        { exitCode: 0, stdout: JSON.generate([{ id: "session-1" }]) }
      else
        { exitCode: 0, stdout: "[]" }
      end
    end

    CodexBar::Core::Process.stub(:run_command, result) do
      CodexBar::Runtime::LocalUsage.opencode_messages("/tmp/opencode.db", Time.utc(2026, 9, 14), providers: :opencode_go_only)
      CodexBar::Runtime::LocalUsage.opencode_messages("/tmp/opencode.db", Time.utc(2026, 9, 14), providers: :zai_only)
    end

    assert_includes calls[1].last, "json_extract(data, '$.providerID') = 'opencode-go'"
    assert_includes calls[3].last, "IN ('zai-coding-plan', 'zai')"
  end

  def test_scan_opencode_counts_only_opencode_go_provider_rows
    rows = [
      {
        date: "2026-09-14",
        model_id: "deepseek-v4.1-flash",
        records: 2,
        input_tokens: 100,
        cached_input_tokens: 0,
        output_tokens: 50,
        reasoning_output_tokens: 0,
        total_tokens: 150,
        cost: 0.02
      }
    ]
    queries = []
    result = lambda do |_command, args, **_options|
      queries << args.last
      if args.last.include?("SELECT id FROM session")
        { exitCode: 0, stdout: JSON.generate([{ id: "session-1" }]) }
      else
        { exitCode: 0, stdout: JSON.generate(rows) }
      end
    end

    previous = ENV["CODEXBAR_OPENCODE_DB"]
    Dir.mktmpdir("codexbar-opencode") do |dir|
      db_path = File.join(dir, "opencode.db")
      File.write(db_path, "")
      ENV["CODEXBAR_OPENCODE_DB"] = db_path
      summary = nil
      CodexBar::Core::Process.stub(:run_command, result) do
        summary = CodexBar::Runtime::LocalUsage.scan_opencode(Time.now.utc - 86_400)
      end

      assert_equal "opencode", summary[:provider]
      assert_equal 150, summary[:totalTokens]
      assert_includes queries.last, "json_extract(data, '$.providerID') = 'opencode-go'"
    ensure
      ENV["CODEXBAR_OPENCODE_DB"] = previous
    end
  end

  def test_scan_zai_reads_zai_routed_messages_from_opencode_database
    rows = [
      {
        date: "2026-09-14",
        model_id: "glm-5.3-flash",
        records: 3,
        input_tokens: 100,
        cached_input_tokens: 10,
        output_tokens: 200,
        reasoning_output_tokens: 5,
        total_tokens: 315,
        cost: 0.0
      }
    ]
    result = lambda do |_command, args, **_options|
      if args.last.include?("SELECT id FROM session")
        { exitCode: 0, stdout: JSON.generate([{ id: "session-1" }]) }
      else
        { exitCode: 0, stdout: JSON.generate(rows) }
      end
    end

    previous = ENV["CODEXBAR_OPENCODE_DB"]
    Dir.mktmpdir("codexbar-zai") do |dir|
      db_path = File.join(dir, "opencode.db")
      File.write(db_path, "")
      ENV["CODEXBAR_OPENCODE_DB"] = db_path
      summary = nil
      CodexBar::Core::Process.stub(:run_command, result) do
        summary = CodexBar::Runtime::LocalUsage.scan_zai(Time.now.utc - 86_400)
      end

      assert_equal "zai", summary[:provider]
      assert_equal true, summary[:supported]
      assert_equal 3, summary[:records]
      assert_equal 315, summary[:totalTokens]
      assert_equal "glm-5.3-flash", summary[:models].keys.first
    ensure
      ENV["CODEXBAR_OPENCODE_DB"] = previous
    end
  end

  def test_scan_zai_reports_supported_without_database
    Dir.mktmpdir("codexbar-zai") do |dir|
      previous = ENV["CODEXBAR_OPENCODE_DB"]
      ENV["CODEXBAR_OPENCODE_DB"] = File.join(dir, "missing.db")

      summary = CodexBar::Runtime::LocalUsage.scan_zai(Time.now.utc - 86_400)

      assert_equal true, summary[:supported]
      assert_equal 0, summary[:records]
    ensure
      ENV["CODEXBAR_OPENCODE_DB"] = previous
    end
  end
end
