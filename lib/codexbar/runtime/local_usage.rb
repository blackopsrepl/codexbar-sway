# frozen_string_literal: true

require "find"
require "json"
require "time"

module CodexBar
  module Runtime
    module LocalUsage
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
            "gemini" => unsupported_provider("gemini")
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

      def unsupported_provider(provider)
        empty_summary(provider, supported: false).merge(
          note: "No trustworthy local usage log source is implemented for #{provider}."
        )
      end

      def add_usage(summary, timestamp, usage)
        input = usage[:input_tokens].to_i
        cached = usage[:cached_input_tokens].to_i + usage[:cache_creation_input_tokens].to_i + usage[:cache_read_input_tokens].to_i
        output = usage[:output_tokens].to_i
        reasoning = usage[:reasoning_output_tokens].to_i
        total = usage[:total_tokens].to_i
        total = input + cached + output + reasoning if total.zero?

        summary[:records] += 1
        summary[:inputTokens] += input
        summary[:cachedInputTokens] += cached
        summary[:outputTokens] += output
        summary[:reasoningOutputTokens] += reasoning
        summary[:totalTokens] += total

        daily = day_entry(summary, timestamp)
        daily[:records] += 1
        daily[:inputTokens] += input
        daily[:cachedInputTokens] += cached
        daily[:outputTokens] += output
        daily[:reasoningOutputTokens] += reasoning
        daily[:totalTokens] += total
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
          totalTokens: 0,
          cost: nil,
          daily: []
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
              totalTokens: 0,
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
