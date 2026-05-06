# frozen_string_literal: true

require "base64"
require "json"

module CodexBar
  module Providers
    module Gemini
      module_function

      def fetch(config)
        source = config[:source] == "cli" ? "cli" : "api"
        home = Dir.home
        settings_path = File.join(home, ".gemini", "settings.json")
        creds_path = File.join(home, ".gemini", "oauth_creds.json")

        settings = load_json(settings_path)
        auth_type = settings[:authType]
        if %w[api-key vertex-ai].include?(auth_type)
          raise "Gemini auth type #{auth_type} is not supported by the Linux rewrite."
        end

        creds = load_json(creds_path)
        access_token = resolve_access_token(creds_path, creds)
        claims = decode_jwt_claims(creds[:id_token])
        code_assist = load_code_assist(access_token)
        project_id = extract_project_id(code_assist) || discover_project_id(access_token)
        quota = load_quota(access_token, project_id)

        model_quotas = coalesce_model_quotas(Array(quota[:buckets]))
        pro = model_quotas.select { |entry| entry[:modelId].downcase.include?("pro") }.min_by { |entry| entry[:percentLeft] }
        flash = model_quotas.select { |entry| entry[:modelId].downcase.include?("flash") }.min_by { |entry| entry[:percentLeft] }

        usage = {
          primary: pro ? quota_to_window(pro) : nil,
          secondary: flash ? quota_to_window(flash) : nil,
          updatedAt: Time.now.utc.iso8601,
          identity: {
            providerID: "gemini",
            accountEmail: claims[:email].is_a?(String) ? claims[:email] : nil,
            loginMethod: gemini_plan(code_assist.dig(:currentTier, :id), claims[:hd])
          }
        }

        {
          provider: "gemini",
          source: source,
          usage: usage,
          notes: []
        }
      rescue StandardError => e
        {
          provider: "gemini",
          source: source,
          notes: [],
          error: e.message
        }
      end

      def resolve_access_token(creds_path, creds)
        access_token = creds[:access_token].to_s
        raise "Gemini OAuth credentials missing access token." if access_token.empty?

        expiry_date = creds[:expiry_date].to_i
        return access_token if expiry_date.zero? || expiry_date > (Time.now.to_f * 1000).to_i
        raise "Gemini token expired and no refresh token is available." if creds[:refresh_token].to_s.empty?

        oauth_client = find_oauth_client
        raise "Could not find Gemini CLI OAuth client metadata for token refresh." unless oauth_client

        response = Core::Http.request(
          "POST",
          "https://oauth2.googleapis.com/token",
          form: {
            client_id: oauth_client[:clientId],
            client_secret: oauth_client[:clientSecret],
            refresh_token: creds[:refresh_token],
            grant_type: "refresh_token"
          }
        )
        raise "Gemini token refresh failed with HTTP #{response.status}." unless response.status.between?(200, 299)

        refreshed = Core::Http.parse_json(response)
        new_access_token = refreshed[:access_token].to_s
        raise "Gemini token refresh did not return an access token." if new_access_token.empty?

        creds[:access_token] = new_access_token
        creds[:expiry_date] = (Time.now.to_f * 1000).to_i + refreshed.fetch(:expires_in, 3600).to_i * 1000
        creds[:id_token] = refreshed[:id_token] if refreshed[:id_token]
        File.write(creds_path, "#{JSON.pretty_generate(creds)}\n")
        new_access_token
      end

      def load_code_assist(access_token)
        response = Core::Http.request(
          "POST",
          "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
          headers: { "Authorization" => "Bearer #{access_token}" },
          json: { metadata: { ideType: "GEMINI_CLI", pluginType: "GEMINI" } }
        )
        return {} unless response.status.between?(200, 299)

        Core::Http.parse_json(response)
      end

      def load_quota(access_token, project_id)
        response = Core::Http.request(
          "POST",
          "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
          headers: { "Authorization" => "Bearer #{access_token}" },
          json: project_id ? { project: project_id } : {}
        )
        raise "Gemini quota request failed with HTTP #{response.status}." unless response.status.between?(200, 299)

        Core::Http.parse_json(response)
      end

      def discover_project_id(access_token)
        response = Core::Http.request(
          "GET",
          "https://cloudresourcemanager.googleapis.com/v1/projects",
          headers: { "Authorization" => "Bearer #{access_token}" }
        )
        return nil unless response.status.between?(200, 299)

        payload = Core::Http.parse_json(response)
        Array(payload[:projects]).each do |project|
          project_id = project[:projectId]
          next unless project_id

          return project_id if project_id.start_with?("gen-lang-client")
          return project_id if project.dig(:labels, :"generative-language")
        end

        nil
      end

      def extract_project_id(response)
        project = response[:cloudaicompanionProject]
        return project if project.is_a?(String)
        return nil unless project.is_a?(Hash)

        project[:id] || project[:projectId]
      end

      def coalesce_model_quotas(buckets)
        map = {}
        buckets.each do |bucket|
          next unless bucket[:modelId] && !bucket[:remainingFraction].nil?

          percent_left = bucket[:remainingFraction].to_f * 100.0
          current = map[bucket[:modelId]]
          if current.nil? || percent_left < current[:percentLeft]
            map[bucket[:modelId]] = { percentLeft: percent_left, resetTime: bucket[:resetTime] }
          end
        end

        map.sort_by { |model_id, _| model_id }.map do |model_id, value|
          value.merge(modelId: model_id)
        end
      end

      def quota_to_window(quota)
        {
          usedPercent: [0, 100 - quota[:percentLeft].to_f].max,
          windowMinutes: nil,
          resetsAt: quota[:resetTime],
          resetDescription: nil
        }
      end

      def gemini_plan(tier_id, hosted_domain)
        return "Paid" if tier_id == "standard-tier"
        return "Workspace" if tier_id == "free-tier" && hosted_domain.is_a?(String) && !hosted_domain.empty?
        return "Free" if tier_id == "free-tier"
        return "Legacy" if tier_id == "legacy-tier"

        nil
      end

      def decode_jwt_claims(token)
        return {} unless token

        parts = token.split(".")
        return {} if parts.length < 2

        payload = parts[1]
        payload = payload + ("=" * ((4 - payload.length % 4) % 4))
        JSON.parse(Base64.urlsafe_decode64(payload), symbolize_names: true)
      rescue ArgumentError, JSON::ParserError
        {}
      end

      def find_oauth_client
        candidates = [
          ENV["GEMINI_CLI_PATH"],
          "/usr/bin/gemini",
          "/usr/local/bin/gemini",
          File.join(Dir.home, ".bun", "bin", "gemini")
        ].compact

        candidates.each do |candidate|
          bin_dir = File.dirname(candidate)
          base_dir = File.dirname(bin_dir)
          possible_paths = [
            File.join(base_dir, "libexec/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"),
            File.join(base_dir, "lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"),
            File.join(base_dir, "share/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"),
            File.join(base_dir, "../gemini-cli-core/dist/src/code_assist/oauth2.js"),
            File.join(base_dir, "node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js")
          ]

          possible_paths.each do |path|
            next unless File.file?(path)

            content = File.read(path)
            client_id = content[/OAUTH_CLIENT_ID\s*=\s*['"]([\w\-.]+)['"]/, 1]
            client_secret = content[/OAUTH_CLIENT_SECRET\s*=\s*['"]([\w-]+)['"]/, 1]
            next unless client_id && client_secret

            return { clientId: client_id, clientSecret: client_secret }
          end
        end

        nil
      end

      def load_json(path)
        JSON.parse(File.read(path), symbolize_names: true)
      end
    end
  end
end
