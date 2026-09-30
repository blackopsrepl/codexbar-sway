# frozen_string_literal: true

require "json"

module TokenMaxx
  module Runtime
    # Reads Hermes Agent's own usage accounting so providers driven through
    # Hermes are counted cumulatively with the CLI logs TokenMaxx already scans.
    #
    # Hermes books every API call in `session_model_usage` (state.db), including
    # auxiliary work (title generation, approvals, background review) under its
    # own `task` id. That table is the only place auxiliary usage is recorded —
    # it is never folded into the per-session counters — so reading it cannot
    # double-count against anything else, and rows are attributable by
    # `billing_provider` rather than by client.
    #
    # Two properties of the source are deliberate, not approximations:
    #
    # * Attribution is product-exact. A Hermes provider id is mapped only when it
    #   names the same product TokenMaxx meters; everything else is reported in
    #   `unattributedProviders` instead of being guessed into a meter.
    # * Hermes flushes token counters through an asynchronous accounting queue,
    #   so a call that just finished may still be missing from the database. The
    #   scanner therefore converges within seconds rather than being exact at the
    #   instant it runs.
    module HermesUsage
      SOURCE_ID = "hermes"
      DB_TIMEOUT_MS = 15_000

      # Hermes billing provider id -> TokenMaxx provider id.
      #
      # Only ids naming the same subscription TokenMaxx meters are mapped.
      # `opencode-zen` and `opencode` are the Zen and free gateways rather than
      # the Go subscription, `openai-api` is platform billing rather than the
      # ChatGPT/Codex plan, `ollama` is a local server without an account
      # allowance, and `anthropic`, `gemini`, `vertex`, and every other id have
      # no TokenMaxx meter of their own. Those rows are preserved in
      # `unattributedProviders` so the omission stays visible; `anthropic` is
      # mapped because Hermes routes the Claude subscription through it, and an
      # Anthropic API key driven through Hermes can be excluded with
      # `localUsage.hermesSkipProviders`.
      PROVIDER_MAP = {
        "opencode-go" => "opencode",
        "zai" => "zai",
        "ollama-cloud" => "ollama",
        "openai-codex" => "codex",
        "anthropic" => "claude",
        "gemini" => "gemini"
      }.freeze

      module_function

      # Returns the Hermes contribution for the given scan window:
      #
      #   { available:, dbPath:, note:, coverage:, providers:, unattributedProviders: }
      #
      # `providers` maps a TokenMaxx provider id to its grouped rows, `coverage`
      # lists every provider the source feeds when it is readable, and
      # `unattributedProviders` accounts for rows that were deliberately not
      # attributed (unmapped ids and skipped providers).
      def read(cutoff, skip_providers: [])
        path = db_path
        return unavailable(nil, nil) unless path && File.file?(path)

        result = usage_rows(path, cutoff)
        return unavailable(path, result[:error]) if result[:error]

        group_rows(result[:rows], path, skip_providers)
      end

      # The provider ids this source feeds. Coverage is a property of the
      # mapping and the skip list, not of the rows found, so a provider whose
      # Hermes traffic happens to be zero in the window is still reported as
      # covered.
      def coverage(skip_providers = [])
        skipped = Array(skip_providers).map(&:to_s)
        (PROVIDER_MAP.values.uniq - skipped).sort
      end

      def db_path
        override = ENV["TOKENMAXX_HERMES_DB"].to_s.strip
        return override unless override.empty?

        hermes_home = ENV["HERMES_HOME"].to_s.strip
        return File.join(hermes_home, "state.db") unless hermes_home.empty?

        File.join(home_dir, ".hermes", "state.db")
      end

      # One bounded query for the whole window. Rows are grouped in SQLite so a
      # large state.db costs the same as a small one, and the day is the UTC day
      # of the row's last activity, falling back to the session start for rows
      # written before Hermes recorded activity timestamps.
      def usage_query(cutoff)
        <<~SQL
          SELECT
            strftime('%Y-%m-%d', COALESCE(u.last_seen, s.started_at, u.first_seen), 'unixepoch') AS date,
            u.billing_provider AS billing_provider,
            COALESCE(u.model, '') AS model_id,
            SUM(COALESCE(u.api_call_count, 0)) AS records,
            SUM(COALESCE(u.input_tokens, 0)) AS input_tokens,
            SUM(COALESCE(u.cache_read_tokens, 0) + COALESCE(u.cache_write_tokens, 0)) AS cached_input_tokens,
            SUM(COALESCE(u.output_tokens, 0)) AS output_tokens,
            SUM(COALESCE(u.reasoning_tokens, 0)) AS reasoning_output_tokens,
            SUM(COALESCE(u.input_tokens, 0) + COALESCE(u.cache_read_tokens, 0) + COALESCE(u.cache_write_tokens, 0) +
                COALESCE(u.output_tokens, 0) + COALESCE(u.reasoning_tokens, 0)) AS total_tokens,
            SUM(COALESCE(u.actual_cost_usd, 0)) AS cost
          FROM session_model_usage u
          JOIN sessions s ON s.id = u.session_id
          WHERE COALESCE(u.last_seen, s.started_at, u.first_seen) >= #{format('%.3f', cutoff.to_f)}
          GROUP BY date, u.billing_provider, model_id
          ORDER BY date
        SQL
      end

      def usage_rows(path, cutoff)
        result = Core::Process.run_command("sqlite3", ["-json", path, usage_query(cutoff)], timeout_ms: DB_TIMEOUT_MS)
        unless result[:exitCode].zero?
          return { error: "The Hermes usage database could not be read (sqlite3 exited #{result[:exitCode]})." }
        end

        stdout = result[:stdout].to_s.strip
        { rows: stdout.empty? ? [] : JSON.parse(stdout, symbolize_names: true) }
      rescue Errno::ENOENT
        { error: "The sqlite3 binary is unavailable to read the Hermes usage database." }
      rescue JSON::ParserError
        { error: "The Hermes usage database returned malformed JSON." }
      end

      def group_rows(rows, path, skip_providers)
        skipped = Array(skip_providers).map(&:to_s)
        providers = {}
        unattributed = {}

        Array(rows).each do |row|
          billing = row[:billing_provider].to_s.strip
          provider = PROVIDER_MAP[billing]
          provider = nil if provider && skipped.include?(provider)

          if provider.nil?
            key = billing.empty? ? "unknown" : billing
            entry = unattributed[key] ||= { provider: key, records: 0, totalTokens: 0 }
            entry[:records] += row[:records].to_i
            entry[:totalTokens] += row[:total_tokens].to_i
            next
          end

          (providers[provider] ||= []) << row
        end

        {
          available: true,
          dbPath: path,
          note: nil,
          coverage: coverage(skip_providers),
          providers: providers,
          unattributedProviders: unattributed.values.sort_by { |entry| [-entry[:totalTokens], entry[:provider]] }
        }
      end

      def unavailable(path, note)
        {
          available: false,
          dbPath: path,
          note: note,
          coverage: [],
          providers: {},
          unattributedProviders: []
        }
      end

      def home_dir
        ENV["TOKENMAXX_HOME"] || Dir.home
      end
    end
  end
end
