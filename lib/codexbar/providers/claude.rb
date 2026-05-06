# frozen_string_literal: true

require "json"

module CodexBar
  module Providers
    module Claude
      DEFAULT_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e" # gitleaks:allow

      module_function

      def fetch(config)
        source = config[:source] == "cli" ? "claude" : "oauth"
        credentials_path = File.join(Dir.home, ".claude", ".credentials.json")
        credentials = load_credentials(credentials_path)
        access_token = resolve_access_token(credentials_path, credentials)

        response = Core::Http.request(
          "GET",
          "https://api.anthropic.com/api/oauth/usage",
          headers: {
            "Authorization" => "Bearer #{access_token}",
            "Accept" => "application/json",
            "Content-Type" => "application/json",
            "anthropic-beta" => "oauth-2025-04-20",
            "User-Agent" => "claude-code/2.1.0"
          }
        )

        raise "Claude OAuth request unauthorized. Run `claude` to re-authenticate." if response.status == 401
        raise "Claude OAuth error: HTTP #{response.status}" unless response.status.between?(200, 299)

        payload = Core::Http.parse_json(response)
        usage = {
          primary: make_window(payload[:five_hour], 300),
          secondary: make_window(payload[:seven_day], 10_080),
          tertiary: make_window(payload[:seven_day_sonnet] || payload[:seven_day_opus], 10_080),
          providerCost: make_extra_usage(payload[:extra_usage]),
          updatedAt: Time.now.utc.iso8601,
          identity: {
            providerID: "claude",
            loginMethod: claude_login_method(credentials.dig(:claudeAiOauth, :rateLimitTier))
          }
        }

        {
          provider: "claude",
          source: source,
          usage: usage,
          notes: []
        }
      rescue StandardError => e
        {
          provider: "claude",
          source: source,
          notes: [],
          error: e.message
        }
      end

      def load_credentials(credentials_path)
        parsed = JSON.parse(File.read(credentials_path), symbolize_names: true)
        unless parsed.dig(:claudeAiOauth, :accessToken).to_s.strip.length.positive?
          raise "Claude OAuth credentials not found. Run `claude` to log in."
        end

        parsed
      end

      def resolve_access_token(credentials_path, credentials)
        oauth = credentials.fetch(:claudeAiOauth)
        access_token = oauth[:accessToken].to_s.strip
        raise "Claude OAuth access token missing." if access_token.empty?

        expires_at = oauth[:expiresAt] ? Time.at(oauth[:expiresAt].to_f / 1000.0) : nil
        return access_token if expires_at.nil? || expires_at > Time.now
        raise "Claude OAuth token expired and no refresh token is available." if oauth[:refreshToken].to_s.empty?

        response = Core::Http.request(
          "POST",
          "https://platform.claude.com/v1/oauth/token",
          form: {
            grant_type: "refresh_token",
            refresh_token: oauth[:refreshToken],
            client_id: ENV["CODEXBAR_CLAUDE_OAUTH_CLIENT_ID"] || DEFAULT_CLIENT_ID
          }
        )
        raise "Claude OAuth refresh failed with HTTP #{response.status}." unless response.status.between?(200, 299)

        refreshed = Core::Http.parse_json(response)
        access_token = refreshed[:access_token].to_s
        raise "Claude OAuth refresh response did not contain an access token." if access_token.empty?

        credentials[:claudeAiOauth] = oauth.merge(
          accessToken: access_token,
          refreshToken: refreshed[:refresh_token] || oauth[:refreshToken],
          expiresAt: ((Time.now.to_f * 1000).to_i + refreshed.fetch(:expires_in, 3600).to_i * 1000)
        )
        File.write(credentials_path, "#{JSON.pretty_generate(credentials)}\n")
        access_token
      end

      def make_window(window, minutes)
        utilization = window&.dig(:utilization)
        return nil if utilization.nil?

        {
          usedPercent: utilization.to_f,
          windowMinutes: minutes,
          resetsAt: window[:resets_at],
          resetDescription: nil
        }
      end

      def make_extra_usage(extra)
        return nil unless extra&.dig(:is_enabled)
        return nil if extra[:used_credits].nil? || extra[:monthly_limit].nil?

        {
          used: extra[:used_credits].to_f / 100.0,
          limit: extra[:monthly_limit].to_f / 100.0,
          currencyCode: extra[:currency].to_s.strip.empty? ? "USD" : extra[:currency].to_s.strip,
          period: "Monthly",
          updatedAt: Time.now.utc.iso8601
        }
      end

      def claude_login_method(rate_limit_tier)
        tier = rate_limit_tier.to_s.strip.downcase
        return nil if tier.empty?
        return "Claude Max" if tier.include?("max")
        return "Claude Pro" if tier.include?("pro")
        return "Claude Team" if tier.include?("team")
        return "Claude Enterprise" if tier.include?("enterprise")

        nil
      end
    end
  end
end
