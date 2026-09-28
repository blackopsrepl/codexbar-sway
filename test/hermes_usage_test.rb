# frozen_string_literal: true

require_relative "test_helper"

class HermesUsageTest < Minitest::Test
  HERMES = CodexBar::Runtime::HermesUsage

  def test_maps_only_the_products_codexbar_meters
    assert_equal "opencode", HERMES::PROVIDER_MAP["opencode-go"]
    assert_equal "zai", HERMES::PROVIDER_MAP["zai"]
    assert_equal "ollama", HERMES::PROVIDER_MAP["ollama-cloud"]
    assert_equal "codex", HERMES::PROVIDER_MAP["openai-codex"]
    assert_equal "claude", HERMES::PROVIDER_MAP["anthropic"]
    assert_equal "gemini", HERMES::PROVIDER_MAP["gemini"]
  end

  def test_products_codexbar_does_not_meter_stay_unmapped
    %w[opencode opencode-zen openai-api openai ollama vertex deepseek xai alibaba bedrock lmstudio].each do |billing|
      assert_nil HERMES::PROVIDER_MAP[billing], "#{billing} must not be attributed to a CodexBar provider"
    end
  end

  def test_read_groups_rows_by_provider_and_accounts_for_unattributed_rows
    with_hermes_db do |path|
      stub_hermes_rows([
        hermes_row(provider: "opencode-go", model: "deepseek-v4.1-flash", records: 2, input: 100, cached: 300, total: 400),
        hermes_row(provider: "openai-api", model: "gpt-6", records: 1, input: 70, total: 70)
      ]) do
        result = HERMES.read(Time.now.utc - 86_400)

        assert_equal true, result[:available]
        assert_equal path, result[:dbPath]
        assert_nil result[:note]
        assert_equal %w[claude codex gemini ollama opencode zai], result[:coverage]
        assert_equal 1, result[:providers]["opencode"].length
        assert_equal 2, result[:providers]["opencode"].first[:records]
        assert_equal [{ provider: "openai-api", records: 1, totalTokens: 70 }], result[:unattributedProviders]
      end
    end
  end

  def test_skipped_providers_are_recorded_as_unattributed_instead_of_attributed
    with_hermes_db do |path|
      stub_hermes_rows([
        hermes_row(provider: "anthropic", model: "claude-sonnet-4-5", records: 4, input: 900, total: 900)
      ]) do
        result = HERMES.read(Time.now.utc - 86_400, skip_providers: ["claude"])

        assert_equal path, result[:dbPath]
        assert_nil result[:providers]["claude"]
        refute_includes result[:coverage], "claude"
        assert_equal [{ provider: "anthropic", records: 4, totalTokens: 900 }], result[:unattributedProviders]
      end
    end
  end

  def test_read_reports_unavailable_without_a_database
    Dir.mktmpdir("codexbar-hermes") do |dir|
      with_env("CODEXBAR_HERMES_DB", File.join(dir, "missing.db")) do
        result = HERMES.read(Time.now.utc - 86_400)

        assert_equal false, result[:available]
        assert_nil result[:note]
        assert_empty result[:providers]
        assert_empty result[:coverage]
      end
    end
  end

  def test_read_reports_a_note_when_sqlite_is_unavailable
    with_hermes_db do |_path|
      CodexBar::Core::Process.stub(:run_command, ->(*_args, **_options) { raise Errno::ENOENT }) do
        result = HERMES.read(Time.now.utc - 86_400)

        assert_equal false, result[:available]
        assert_includes result[:note], "sqlite3 binary is unavailable"
      end
    end
  end

  def test_read_reports_a_note_when_the_query_fails
    with_hermes_db do |_path|
      CodexBar::Core::Process.stub(:run_command, ->(*_args, **_options) { { exitCode: 1, stdout: "", stderr: "no such table" } }) do
        result = HERMES.read(Time.now.utc - 86_400)

        assert_equal false, result[:available]
        assert_includes result[:note], "could not be read"
      end
    end
  end

  def test_usage_query_scopes_by_activity_timestamp_and_groups_in_sqlite
    cutoff = Time.utc(2026, 9, 28, 12, 0)
    sql = HERMES.usage_query(cutoff)

    assert_includes sql, "FROM session_model_usage u"
    assert_includes sql, "JOIN sessions s ON s.id = u.session_id"
    assert_includes sql, "COALESCE(u.last_seen, s.started_at, u.first_seen)"
    assert_includes sql, "GROUP BY date, u.billing_provider, model_id"
    assert_includes sql, format("%.3f", cutoff.to_f)
  end

  def test_db_path_follows_environment_overrides
    with_env("CODEXBAR_HERMES_DB", nil) do
      with_env("HERMES_HOME", "/srv/hermes-home") do
        assert_equal "/srv/hermes-home/state.db", HERMES.db_path
      end
      with_env("HERMES_HOME", nil) do
        with_temp_home do |home|
          assert_equal File.join(home, ".hermes", "state.db"), HERMES.db_path
        end
      end
      assert_equal "/tmp/explicit.db", with_env("CODEXBAR_HERMES_DB", "/tmp/explicit.db") { HERMES.db_path }
    end
  end

  def test_reads_a_real_state_database_with_activity_and_fallback_timestamps
    skip_without_sqlite3
    now = Time.now.utc
    recent = now - 3_600
    stale = now - (10 * 86_400)

    Dir.mktmpdir("codexbar-hermes") do |dir|
      path = File.join(dir, "state.db")
      build_state_database(
        path,
        sessions: [
          { id: "ses_recent", started_at: recent.to_f },
          { id: "ses_stale", started_at: stale.to_f },
          { id: "ses_untimestamped", started_at: recent.to_f }
        ],
        usage: [
          # Main loop plus an auxiliary task: same session, same model, two rows.
          { session_id: "ses_recent", model: "deepseek-v4.1-flash", billing_provider: "opencode-go",
            task: "", calls: 2, input: 1000, cache_read: 3000, output: 100, last_seen: recent.to_f },
          { session_id: "ses_recent", model: "deepseek-v4.1-flash", billing_provider: "opencode-go",
            task: "approval", calls: 3, input: 50, output: 5, last_seen: recent.to_f },
          # Outside the scan window: must not be counted.
          { session_id: "ses_stale", model: "deepseek-v4.1-flash", billing_provider: "opencode-go",
            task: "", calls: 9, input: 99_999, output: 99_999, last_seen: stale.to_f },
          # No activity timestamps anywhere: falls back to the session start.
          { session_id: "ses_untimestamped", model: "glm-5.3-flash", billing_provider: "zai",
            task: "", calls: 1, input: 111, output: 11 },
          # Unmapped billing provider: preserved, never attributed.
          { session_id: "ses_recent", model: "gpt-6-sol", billing_provider: "openai-api",
            task: "", calls: 1, input: 700, output: 70, last_seen: recent.to_f }
        ]
      )

      with_env("CODEXBAR_HERMES_DB", path) do
        # A two-day window excludes the ten-day-old session below.
        result = HERMES.read(now - (2 * 86_400))
        day = recent.utc.strftime("%Y-%m-%d")

        opencode = result[:providers]["opencode"]
        assert_equal 1, opencode.length, "rows are grouped by day and model"
        assert_equal 5, opencode.first[:records]
        assert_equal 1050, opencode.first[:input_tokens]
        assert_equal 3000, opencode.first[:cached_input_tokens]
        assert_equal 105, opencode.first[:output_tokens]
        assert_equal 4155, opencode.first[:total_tokens]
        assert_equal day, opencode.first[:date]

        zai = result[:providers]["zai"]
        assert_equal 122, zai.first[:total_tokens]
        assert_equal day, zai.first[:date]

        assert_equal [{ provider: "openai-api", records: 1, totalTokens: 770 }], result[:unattributedProviders]
      end
    end
  end

  private

  def hermes_row(provider:, model: "deepseek-v4.1-flash", date: nil, records: 1, input: 0, cached: 0, output: 0,
                 reasoning: 0, total: nil, cost: 0.0)
    {
      date: date || Time.now.utc.strftime("%Y-%m-%d"),
      billing_provider: provider,
      model_id: model,
      records: records,
      input_tokens: input,
      cached_input_tokens: cached,
      output_tokens: output,
      reasoning_output_tokens: reasoning,
      total_tokens: total || (input + cached + output + reasoning),
      cost: cost
    }
  end

  def with_hermes_db
    Dir.mktmpdir("codexbar-hermes") do |dir|
      path = File.join(dir, "state.db")
      File.write(path, "")
      with_env("CODEXBAR_HERMES_DB", path) { yield path }
    end
  end

  def stub_hermes_rows(rows)
    result = lambda do |_command, args, **_options|
      if args.last.to_s.include?("session_model_usage")
        { exitCode: 0, stdout: JSON.generate(rows) }
      else
        { exitCode: 0, stdout: "[]" }
      end
    end

    CodexBar::Core::Process.stub(:run_command, result) { yield }
  end

  def with_env(name, value)
    previous = ENV[name]
    if value.nil?
      ENV.delete(name)
    else
      ENV[name] = value
    end
    yield
  ensure
    if previous.nil?
      ENV.delete(name)
    else
      ENV[name] = previous
    end
  end

  def skip_without_sqlite3
    path = CodexBar::Core::Process.executable_path("sqlite3")
    skip("sqlite3 is unavailable") if path.to_s.strip.empty?
  end

  def build_state_database(path, sessions:, usage:)
    session_rows = sessions.map do |session|
      "INSERT INTO sessions (id, started_at) VALUES ('#{session[:id]}', #{format('%.3f', session[:started_at])});"
    end
    usage_rows = usage.map do |row|
      values = {
        session_id: row[:session_id],
        model: row[:model],
        billing_provider: row[:billing_provider],
        task: row[:task],
        api_call_count: row[:calls],
        input_tokens: row[:input].to_i,
        cached_input_tokens: row[:cache_read].to_i,
        output_tokens: row[:output].to_i,
        actual_cost_usd: row[:cost].to_f,
        last_seen: row[:last_seen] ? format("%.3f", row[:last_seen]) : "NULL",
        first_seen: row[:last_seen] ? format("%.3f", row[:last_seen]) : "NULL"
      }
      "INSERT INTO session_model_usage (session_id, model, billing_provider, billing_base_url, billing_mode, task, " \
        "api_call_count, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens, " \
        "estimated_cost_usd, actual_cost_usd, first_seen, last_seen) VALUES " \
        "('#{values[:session_id]}', '#{values[:model]}', '#{values[:billing_provider]}', '', '', '#{values[:task]}', " \
        "#{values[:api_call_count]}, #{values[:input_tokens]}, #{values[:output_tokens]}, #{values[:cached_input_tokens]}, " \
        "0, 0, 0.0, #{values[:actual_cost_usd]}, #{values[:first_seen]}, #{values[:last_seen]});"
    end

    sql = <<~SQL
      CREATE TABLE sessions (id text PRIMARY KEY, started_at REAL NOT NULL);
      CREATE TABLE session_model_usage (
        session_id text NOT NULL,
        model text,
        billing_provider text NOT NULL DEFAULT '',
        billing_base_url text NOT NULL DEFAULT '',
        billing_mode text NOT NULL DEFAULT '',
        task text NOT NULL DEFAULT '',
        api_call_count integer NOT NULL DEFAULT 0,
        input_tokens integer NOT NULL DEFAULT 0,
        output_tokens integer NOT NULL DEFAULT 0,
        cache_read_tokens integer NOT NULL DEFAULT 0,
        cache_write_tokens integer NOT NULL DEFAULT 0,
        reasoning_tokens integer NOT NULL DEFAULT 0,
        estimated_cost_usd REAL NOT NULL DEFAULT 0,
        actual_cost_usd REAL NOT NULL DEFAULT 0,
        first_seen REAL,
        last_seen REAL,
        PRIMARY KEY (session_id, model, billing_provider, billing_base_url, billing_mode, task)
      );
      #{session_rows.join("\n")}
      #{usage_rows.join("\n")}
    SQL

    result = CodexBar::Core::Process.run_command("sqlite3", [path, sql])
    assert_equal 0, result[:exitCode], "fixture state database failed to build: #{result[:stderr]}"
  end
end
