# frozen_string_literal: true

require "time"

module CodexBar
  module Runtime
    module Notifications
      module_function

      def process(config, previous_snapshot, snapshot, now: Time.now.utc)
        return State.read_notification_state(config) unless config.dig(:notifications, :enabled)

        state = normalize_state(State.read_notification_state(config))
        provider_states = state[:providers]

        Core::Types::ALL_PROVIDERS.each do |provider|
          provider_states[provider] ||= {}
          current = current_provider_state(config, snapshot, provider)
          previous = provider_states[provider]
          notify_quota_transition(config, provider, previous[:quotaLevel], current[:quotaLevel]) if config.dig(:notifications, :quotaWarnings)
          notify_service_transition(config, provider, previous[:serviceState], current[:serviceState], current[:serviceText]) if config.dig(:notifications, :incidentWarnings)
          provider_states[provider] = current.merge(updatedAt: now.iso8601)
        end

        output = {
          generatedAt: now.iso8601,
          providers: provider_states
        }
        State.write_notification_state(config, output)
        output
      end

      def normalize_state(input)
        {
          generatedAt: input && input[:generatedAt],
          providers: (input && input[:providers] || {}).each_with_object({}) do |(provider, state), output|
            output[provider.to_s] = (state || {}).transform_keys(&:to_sym)
          end
        }
      end

      def current_provider_state(config, snapshot, provider)
        result = State.result_for(snapshot, provider)
        usage = result && result[:usage]
        windows = usage ? Core::Metric.metric_windows(usage) : []
        service = provider_service_status(snapshot, provider)
        {
          quotaLevel: Core::Metric.worst_quota_level(
            windows,
            warning_threshold: config.dig(:notifications, :warningThreshold),
            critical_threshold: config.dig(:notifications, :criticalThreshold)
          ) || "unknown",
          serviceState: service[:state].to_s.empty? ? "unknown" : service[:state].to_s,
          serviceText: Core::Format.service_status_text(service)
        }
      end

      def provider_service_status(snapshot, provider)
        snapshot&.dig(:serviceStatus, :providers, provider) ||
          snapshot&.dig(:serviceStatus, :providers, provider.to_sym) ||
          {}
      end

      def notify_quota_transition(config, provider, previous, current)
        return if previous == current
        return unless %w[warning critical ok].include?(current)
        return if previous.nil? && current == "ok"

        label = Core::Types::PROVIDER_METADATA.fetch(provider)[:label]
        case current
        when "critical"
          notify(config, "CodexBar", "#{label} quota is critical.")
        when "warning"
          notify(config, "CodexBar", "#{label} quota is low.")
        when "ok"
          notify(config, "CodexBar", "#{label} quota recovered.")
        end
      end

      def notify_service_transition(config, provider, previous, current, text)
        return if previous == current
        return unless %w[degraded outage ok].include?(current)
        return if previous.nil? && current == "ok"

        label = Core::Types::PROVIDER_METADATA.fetch(provider)[:label]
        case current
        when "degraded", "outage"
          notify(config, "CodexBar", "#{label} service #{current}: #{text}")
        when "ok"
          notify(config, "CodexBar", "#{label} service recovered.")
        end
      end

      def notify(config, title, message)
        command = config.dig(:runtime, :notificationCommand).to_s.strip
        return if command.empty?

        Core::Process.spawn_detached(command, [title, message])
      rescue StandardError
        nil
      end
    end
  end
end
