# frozen_string_literal: true

require_relative "test_helper"

class StatusTest < Minitest::Test
  def test_statuspage_component_outage_maps_to_outage
    payload = {
      status: { indicator: "none", description: "All Systems Operational" },
      components: [
        { name: "Codex API", status: "major_outage" }
      ],
      incidents: [
        { name: "Codex API outage", status: "investigating", impact: "major" }
      ]
    }
    response = CodexBar::Core::Http::Response.new(status: 200, body: JSON.generate(payload), headers: {})

    CodexBar::Core::Http.stub(:request, response) do
      status = CodexBar::Runtime::Status.fetch_provider("codex")

      assert_equal "outage", status[:state]
      assert_includes status[:description], "Codex API"
      assert_includes status[:incident], "Codex API outage"
    end
  end

  def test_google_gemini_active_incident_maps_to_degraded
    payload = [
      {
        end: nil,
        status: "SERVICE_DISRUPTION",
        external_desc: "Vertex Gemini API customers are seeing elevated errors.",
        affected_products: [{ title: "Vertex Gemini API" }]
      }
    ]
    response = CodexBar::Core::Http::Response.new(status: 200, body: JSON.generate(payload), headers: {})

    CodexBar::Core::Http.stub(:request, response) do
      status = CodexBar::Runtime::Status.fetch_provider("gemini")

      assert_equal "degraded", status[:state]
      assert_includes status[:description], "Vertex Gemini API"
    end
  end

  def test_status_fetch_errors_are_unknown
    CodexBar::Core::Http.stub(:request, ->(*) { raise "boom" }) do
      status = CodexBar::Runtime::Status.fetch_provider("claude")

      assert_equal "unknown", status[:state]
      assert_equal "boom", status[:error]
    end
  end
end
