# frozen_string_literal: true

require "find"
require "json"
require "time"

module CodexBar
  module Runtime
    module LocalUsage
      ZAI_PROVIDER_IDS = %w[zai-coding-plan zai].freeze
      OPENCODE_GO_PROVIDER_ID = "opencode-go"

      module_function

      def read_cache(config)
        State.read_local_usage(config)
      end

      def refresh_if_due(config, force: false, now: Time.now.utc)
        cached = read_cache(config)
        return cached unless force || due?(config, cached, now)

        refresh(config, now: now)
      end

      def refresh(config, now: Time.now.utc)
        scan_days = config.dig(:localUsage, :scanDays).to_i
        cutoff = now - (scan_days * 86_400)
        payload = {
          generatedAt: now.iso8601,
          scanDays: scan_days,
          providers: {
            "codex" => scan_codex(cutoff),
            "claude" => scan_claude(cutoff),
            "gemini" => scan_gemini(cutoff),
            "opencode" => scan_opencode(cutoff),
            "zai" => scan_zai(cutoff)
          }
        }
        State.write_local_usage(config, payload)
        payload
      end

      def due?(config, cached, now = Time.now.utc)
        return false unless config.dig(:localUsage, :enabled)
        generated_at = State.parse_time(cached && cached[:generatedAt])
        return true unless generated_at

        generated_at < (now - config.dig(:localUsage, :refreshSeconds).to_i)
      end

      def scan_codex(cutoff)
        files = jsonl_files(
          File.join(home_dir, ".codex", "sessions"),
          File.join(home_dir, ".codex", "archived_sessions")
        )
        summary = empty_summary("codex", supported: true)
        files.each do |path|
          next unless recent_file?(path, cutoff)

          each_json_line(path) do |record|
            next unless record[:type].to_s == "event_msg"

            usage = record.dig(:payload, :info, :last_token_usage)
            next unless usage

            timestamp = parse_time(record[:timestamp]) || File.mtime(path)
            next if timestamp < cutoff

            add_usage(summary, timestamp, usage)
          end
        end
        finalize_summary(summary)
      end

      def scan_claude(cutoff)
        files = jsonl_files(File.join(home_dir, ".claude", "projects"))
        summary = empty_summary("claude", supported: true)
        files.each do |path|
          next unless recent_file?(path, cutoff)

          each_json_line(path) do |record|
            usage = record.dig(:message, :usage)
            next unless usage

            timestamp = parse_time(record[:timestamp]) || File.mtime(path)
            next if timestamp < cutoff

            add_usage(summary, timestamp, usage)
            add_cost(summary, timestamp, exact_cost(record))
          end
        end
        finalize_summary(summary)
      end

      def scan_gemini(cutoff)
        files = gemini_chat_files
        summary = empty_summary("gemini", supported: true)
        files.each do |path|
          next unless recent_file?(path, cutoff)

          each_json_line(path) do |record|
            next unless record[:type].to_s == "gemini"

            tokens = record[:tokens]
            next unless tokens.is_a?(Hash)

            timestamp = parse_time(record[:timestamp]) || File.mtime(path)
            next if timestamp < cutoff

            add_gemini_usage(summary, timestamp, tokens, record[:model])
          end
        end
        finalize_summary(summary)
      end

      def scan_opencode(cutoff)
        db_path = opencode_db_path
        return empty_summary("opencode", supported: true) unless db_path && File.file?(db_path)

        rows = opencode_messages(db_path, cutoff, providers: :opencode_go_only)
        return empty_summary("opencode", supported: false).merge(
          note: "The sqlite3 binary is unavailable to read the OpenCode usage database."
        ) if rows.nil?

        summarize_opencode_messages(rows)
      end

      def summarize_opencode_messages(rows, provider: "opencode")
        summary = empty_summary(provider, supported: true)
        Array(rows).each do |row|
          timestamp = Time.parse("#{row[:date]}T00:00:00Z")
          records = row[:records].to_i
          input = row[:input_tokens].to_i
          cached = row[:cached_input_tokens].to_i
          output = row[:output_tokens].to_i
          reasoning = row[:reasoning_output_tokens].to_i
          total = row[:total_tokens].to_i
          total = input + cached + output + reasoning if total.zero?
          model_id = row[:model_id].to_s.strip

          usage = {
            input_tokens: input,
            cached_input_tokens: cached,
            output_tokens: output,
            reasoning_output_tokens: reasoning,
            total_tokens: total
          }
          add_usage(summary, timestamp, usage, records: records)
          add_cost(summary, timestamp, row[:cost])
          next if model_id.empty?

          add_model_usage(summary[:models], model_id, input, cached, output, reasoning, 0, total, records: records)
          add_model_usage(day_entry(summary, timestamp)[:models], model_id, input, cached, output, reasoning, 0, total, records: records)
        end
        finalize_summary(summary)
      rescue ArgumentError
        summary
      end

      def opencode_messages(db_path, cutoff, providers: :all)
        cutoff_ms = (cutoff.to_f * 1000).to_i
        session_query = "SELECT id FROM session WHERE time_updated >= #{cutoff_ms}"
        session_result = Core::Process.run_command("sqlite3", ["-json", db_path, session_query], timeout_ms: 15_000)
        return nil unless session_result[:exitCode].zero?

        session_rows = JSON.parse(session_result[:stdout].to_s.strip.empty? ? "[]" : session_result[:stdout], symbolize_names: true)
        session_ids = Array(session_rows).filter_map { |row| row[:id].to_s.strip unless row[:id].to_s.strip.empty? }
        return [] if session_ids.empty?

        quoted_ids = session_ids.map { |id| "'#{id.gsub("'", "''")}'" }.join(", ")
        provider_filter = opencode_provider_filter(providers)
        query = <<~SQL
          SELECT
            strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') AS date,
            json_extract(data, '$.modelID') AS model_id,
            COUNT(*) AS records,
            SUM(COALESCE(json_extract(data, '$.tokens.input'), 0)) AS input_tokens,
            SUM(COALESCE(json_extract(data, '$.tokens.cache.read'), 0) + COALESCE(json_extract(data, '$.tokens.cache.write'), 0)) AS cached_input_tokens,
            SUM(COALESCE(json_extract(data, '$.tokens.output'), 0)) AS output_tokens,
            SUM(COALESCE(json_extract(data, '$.tokens.reasoning'), 0)) AS reasoning_output_tokens,
            SUM(
              COALESCE(json_extract(data, '$.tokens.input'), 0) +
              COALESCE(json_extract(data, '$.tokens.cache.read'), 0) +
              COALESCE(json_extract(data, '$.tokens.cache.write'), 0) +
              COALESCE(json_extract(data, '$.tokens.output'), 0) +
              COALESCE(json_extract(data, '$.tokens.reasoning'), 0)
            ) AS total_tokens,
            SUM(CASE WHEN json_extract(data, '$.cost') IS NOT NULL THEN json_extract(data, '$.cost') END) AS cost
          FROM message
          WHERE session_id IN (#{quoted_ids})
            AND time_created >= #{cutoff_ms}
            AND json_extract(data, '$.role') = 'assistant'
            AND json_type(data, '$.tokens') = 'object'
            #{provider_filter ? "AND #{provider_filter}" : ""}
          GROUP BY date, model_id
        SQL
        result = Core::Process.run_command("sqlite3", ["-json", db_path, query], timeout_ms: 15_000)
        return nil unless result[:exitCode].zero?

        JSON.parse(result[:stdout].to_s.strip.empty? ? "[]" : result[:stdout], symbolize_names: true)
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def opencode_provider_filter(mode)
        zai_ids = ZAI_PROVIDER_IDS.map { |id| "'#{id}'" }.join(", ")
        case mode
        when :zai_only
          "COALESCE(json_extract(data, '$.providerID'), '') IN (#{zai_ids})"
        when :opencode_go_only
          "json_extract(data, '$.providerID') = '#{OPENCODE_GO_PROVIDER_ID}'"
        end
      end

      def opencode_db_path
        ENV["CODEXBAR_OPENCODE_DB"] || File.join(home_dir, ".local", "share", "opencode", "opencode.db")
      end

      def scan_zai(cutoff)
        db_path = opencode_db_path
        return empty_summary("zai", supported: true) unless db_path && File.file?(db_path)

        rows = opencode_messages(db_path, cutoff, providers: :zai_only)
        return empty_summary("zai", supported: false).merge(
          note: "The sqlite3 binary is unavailable to read the OpenCode usage database."
        ) if rows.nil?

        summarize_opencode_messages(rows, provider: "zai")
      end

      def unsupported_provider(provider)
        empty_summary(provider, supported: false).merge(
          note: "No trustworthy local usage log source is implemented for #{provider}."
        )
      end

      def add_usage(summary, timestamp, usage, records: 1)
        input = usage[:input_tokens].to_i
        cached = usage[:cached_input_tokens].to_i + usage[:cache_creation_input_tokens].to_i + usage[:cache_read_input_tokens].to_i
        output = usage[:output_tokens].to_i
        reasoning = usage[:reasoning_output_tokens].to_i
        total = usage[:total_tokens].to_i
        total = input + cached + output + reasoning if total.zero?

        summary[:records] += records
        summary[:inputTokens] += input
        summary[:cachedInputTokens] += cached
        summary[:outputTokens] += output
        summary[:reasoningOutputTokens] += reasoning
        summary[:totalTokens] += total

        daily = day_entry(summary, timestamp)
        daily[:records] += records
        daily[:inputTokens] += input
        daily[:cachedInputTokens] += cached
        daily[:outputTokens] += output
        daily[:reasoningOutputTokens] += reasoning
        daily[:totalTokens] += total
      end

      def add_gemini_usage(summary, timestamp, tokens, model)
        input = tokens[:input].to_i
        cached = tokens[:cached].to_i
        output = tokens[:output].to_i
        reasoning = tokens[:thoughts].to_i
        tool = tokens[:tool].to_i
        total = tokens[:total].to_i
        total = input + output + reasoning + tool if total.zero?

        summary[:records] += 1
        summary[:inputTokens] += input
        summary[:cachedInputTokens] += cached
        summary[:outputTokens] += output
        summary[:reasoningOutputTokens] += reasoning
        summary[:toolTokens] += tool
        summary[:totalTokens] += total

        daily = day_entry(summary, timestamp)
        daily[:records] += 1
        daily[:inputTokens] += input
        daily[:cachedInputTokens] += cached
        daily[:outputTokens] += output
        daily[:reasoningOutputTokens] += reasoning
        daily[:toolTokens] += tool
        daily[:totalTokens] += total

        model_id = model.to_s.strip
        return if model_id.empty?

        add_model_usage(summary[:models], model_id, input, cached, output, reasoning, tool, total)
        add_model_usage(daily[:models], model_id, input, cached, output, reasoning, tool, total)
      end

      def add_model_usage(models, model_id, input, cached, output, reasoning, tool, total, records: 1)
        entry = models[model_id] ||= empty_model_summary(model_id)
        entry[:records] += records
        entry[:inputTokens] += input
        entry[:cachedInputTokens] += cached
        entry[:outputTokens] += output
        entry[:reasoningOutputTokens] += reasoning
        entry[:toolTokens] += tool
        entry[:totalTokens] += total
      end

      def add_cost(summary, timestamp, cost)
        return unless cost

        summary[:cost] ||= 0.0
        summary[:cost] += cost
        daily = day_entry(summary, timestamp)
        daily[:cost] ||= 0.0
        daily[:cost] += cost
      end

      def exact_cost(record)
        values = [
          record[:cost],
          record[:costUSD],
          record.dig(:message, :usage, :cost),
          record.dig(:message, :usage, :cost_usd)
        ]
        value = values.find { |candidate| !candidate.nil? }
        return nil unless value

        number = value.to_f
        number.finite? ? number : nil
      end

      def empty_summary(provider, supported:)
        {
          provider: provider,
          supported: supported,
          records: 0,
          inputTokens: 0,
          cachedInputTokens: 0,
          outputTokens: 0,
          reasoningOutputTokens: 0,
          toolTokens: 0,
          totalTokens: 0,
          cost: nil,
          models: {},
          daily: []
        }
      end

      def empty_model_summary(model_id)
        {
          modelId: model_id,
          records: 0,
          inputTokens: 0,
          cachedInputTokens: 0,
          outputTokens: 0,
          reasoningOutputTokens: 0,
          toolTokens: 0,
          totalTokens: 0
        }
      end

      def day_entry(summary, timestamp)
        date = timestamp.utc.strftime("%Y-%m-%d")
        summary[:daily].find { |entry| entry[:date] == date } ||
          begin
            entry = {
              date: date,
              records: 0,
              inputTokens: 0,
              cachedInputTokens: 0,
              outputTokens: 0,
              reasoningOutputTokens: 0,
              toolTokens: 0,
              totalTokens: 0,
              models: {},
              cost: nil
            }
            summary[:daily] << entry
            entry
          end
      end

      def finalize_summary(summary)
        summary[:daily] = summary[:daily].sort_by { |entry| entry[:date] }
        summary
      end

      def gemini_chat_files
        root = File.join(home_dir, ".gemini", "tmp")
        return [] unless File.directory?(root)

        files = []
        Find.find(root) do |path|
          Find.prune if File.basename(path).start_with?(".") && path != root
          next unless File.file?(path)
          next unless File.extname(path) == ".jsonl"
          next unless path.split(File::SEPARATOR).include?("chats")

          files << path
        end
        files
      rescue Errno::EACCES, Errno::ENOENT
        []
      end

      def jsonl_files(*roots)
        roots.flat_map do |root|
          next [] unless File.directory?(root)

          files = []
          Find.find(root) do |path|
            Find.prune if File.basename(path).start_with?(".") && path != root
            files << path if File.file?(path) && File.extname(path) == ".jsonl"
          end
          files
        rescue Errno::EACCES, Errno::ENOENT
          []
        end
      end

      def recent_file?(path, cutoff)
        File.mtime(path) >= cutoff
      rescue Errno::ENOENT
        false
      end

      def each_json_line(path)
        File.foreach(path) do |line|
          next if line.strip.empty?

          yield JSON.parse(line, symbolize_names: true)
        rescue JSON::ParserError
          next
        end
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end

      def parse_time(value)
        return nil if value.to_s.strip.empty?

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def home_dir
        ENV["CODEXBAR_HOME"] || Dir.home
      end
    end
  end
end
