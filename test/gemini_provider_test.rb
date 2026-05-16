# frozen_string_literal: true

require_relative "test_helper"

class GeminiProviderTest < Minitest::Test
  def test_oauth_client_is_read_from_bundled_gemini_cli_install
    Dir.mktmpdir("codexbar-gemini-cli") do |dir|
      prefix = File.join(dir, "usr", "local")
      bin_dir = File.join(prefix, "bin")
      package_root = File.join(prefix, "lib", "node_modules", "@google", "gemini-cli")
      bundle_dir = File.join(package_root, "bundle")
      FileUtils.mkdir_p([bin_dir, bundle_dir])
      File.write(File.join(package_root, "package.json"), JSON.generate(name: "@google/gemini-cli"))
      File.write(File.join(bundle_dir, "gemini.js"), "#!/usr/bin/env node\n")
      File.write(
        File.join(bundle_dir, "chunk-test.js"),
        <<~JS
          var OAUTH_CLIENT_ID = "test-client.apps.googleusercontent.com";
          var OAUTH_CLIENT_SECRET = "test-secret";
        JS
      )
      File.symlink("../lib/node_modules/@google/gemini-cli/bundle/gemini.js", File.join(bin_dir, "gemini"))

      with_gemini_cli_path(File.join(bin_dir, "gemini")) do
        client = CodexBar::Providers::Gemini.find_oauth_client
        assert_equal "test-client.apps.googleusercontent.com", client[:clientId]
        assert_equal "test-secret", client[:clientSecret]
      end
    end
  end

  def test_quota_meters_preserve_each_model_bucket
    meters = CodexBar::Providers::Gemini.quota_meters([
      { modelId: "gemini-2.5-flash", remainingFraction: 1, resetTime: "2026-05-17T15:22:36Z" },
      { modelId: "gemini-2.5-pro", remainingFraction: 0, resetTime: "1970-01-01T00:00:00Z" },
      { modelId: "gemini-3.1-flash-lite-preview", remainingFraction: 0.998, resetTime: "2026-05-17T13:38:16Z" }
    ])

    assert_equal ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-3.1-flash-lite-preview"], meters.map { |meter| meter[:modelId] }
    assert_equal ["model:gemini-2.5-flash", "model:gemini-2.5-pro", "model:gemini-3.1-flash-lite-preview"], meters.map { |meter| meter[:key] }
    assert_equal 0.0, meters[0][:usedPercent]
    assert_equal 100.0, meters[1][:usedPercent]
    assert_nil meters[1][:resetsAt]
  end

  def test_auth_type_prefers_selected_auth_type_and_flags_unsupported_quota_modes
    provider = CodexBar::Providers::Gemini

    assert_equal "gemini-api-key", provider.gemini_auth_type(authType: "oauth-personal", selectedAuthType: "gemini-api-key")
    assert provider.unsupported_quota_auth_type?("gemini-api-key")
    assert provider.unsupported_quota_auth_type?("vertex-ai")
    refute provider.unsupported_quota_auth_type?("oauth-personal")
  end

  def test_project_id_extraction_accepts_string_and_hash_shapes
    provider = CodexBar::Providers::Gemini

    assert_equal "project-a", provider.extract_project_id(cloudaicompanionProject: "project-a")
    assert_equal "project-b", provider.extract_project_id(cloudaicompanionProject: { id: "project-b" })
    assert_equal "project-c", provider.extract_project_id(cloudaicompanionProject: { projectId: "project-c" })
  end

  private

  def with_gemini_cli_path(path)
    previous = ENV["GEMINI_CLI_PATH"]
    ENV["GEMINI_CLI_PATH"] = path
    yield
  ensure
    ENV["GEMINI_CLI_PATH"] = previous
  end
end
