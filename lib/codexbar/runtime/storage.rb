# frozen_string_literal: true

require "find"
require "time"

module CodexBar
  module Runtime
    module Storage
      PROVIDER_PATHS = {
        "codex" => [".codex"],
        "claude" => [".claude"],
        "gemini" => [".gemini"]
      }.freeze

      module_function

      def read_cache(config)
        State.read_storage(config)
      end

      def refresh_if_due(config, force: false, now: Time.now.utc)
        cached = read_cache(config)
        return cached unless force || due?(config, cached, now)

        refresh(config, now: now)
      end

      def refresh(config, now: Time.now.utc)
        providers = Core::Types::ALL_PROVIDERS.each_with_object({}) do |provider, output|
          output[provider] = scan_provider(provider)
        end
        payload = {
          generatedAt: now.iso8601,
          providers: providers
        }
        State.write_storage(config, payload)
        payload
      end

      def due?(config, cached, now = Time.now.utc)
        return false unless config.dig(:storage, :enabled)
        generated_at = State.parse_time(cached && cached[:generatedAt])
        return true unless generated_at

        generated_at < (now - config.dig(:storage, :refreshSeconds).to_i)
      end

      def scan_provider(provider)
        paths = PROVIDER_PATHS.fetch(provider).map { |relative| File.join(home_dir, relative) }
        entries = paths.map { |path| scan_path(path) }
        {
          provider: provider,
          totalBytes: entries.sum { |entry| entry[:bytes].to_i },
          paths: entries
        }
      end

      def scan_path(path)
        {
          path: path,
          exists: File.exist?(path),
          bytes: File.exist?(path) ? path_bytes(path) : 0
        }
      end

      def path_bytes(path)
        total = 0
        if File.file?(path)
          return File.size(path)
        end

        Find.find(path) do |entry|
          total += File.lstat(entry).size if File.file?(entry)
        rescue Errno::ENOENT, Errno::EACCES
          next
        end
        total
      rescue Errno::ENOENT, Errno::EACCES
        0
      end

      def home_dir
        ENV["CODEXBAR_HOME"] || Dir.home
      end
    end
  end
end
