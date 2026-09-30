# frozen_string_literal: true

require_relative "test_helper"

class ServerTest < Minitest::Test
  def test_health_payload_reports_missing_snapshot
    Dir.mktmpdir("tokenmaxx-state") do |dir|
      config = build_config
      config[:runtime][:stateDir] = dir

      payload = TokenMaxx::Runtime::Server.payload(config, "/health")

      assert_equal true, payload[:ok]
      assert_equal false, payload[:snapshotPresent]
    end
  end
end
