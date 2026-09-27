# frozen_string_literal: true

require "time"

module CodexBar
  module Core
    # Peak versus off-peak rate windows for providers that bill by time of day.
    #
    # The windows are vendor-documented and fixed in UTC; none of the supported
    # provider APIs expose them at runtime (the Ollama usage endpoint returns
    # only fraction windows and the Z.ai quota endpoint only `limits[]`), so they
    # are declared here. Only the standing recurring schedules are encoded:
    # limited-time vendor promotions are intentionally not tracked, because a
    # hardcoded promotion would keep reporting a discount after it expires. When
    # a provider changes a schedule this table must be updated; see
    # docs/providers.md.
    module Peak
      WEEKDAYS = (1..5).freeze
      OFF_PEAK = "offpeak"
      PEAK = "peak"

      # Each schedule lists peak windows as [weekday_range, start_minute,
      # end_minute] in UTC minutes from midnight; everything outside the windows
      # is off-peak. A model pattern restricts a schedule to matching model ids;
      # nil applies it to every model the provider serves.
      SCHEDULES = [
        {
          provider: "zai",
          model: nil,
          peak: [[WEEKDAYS, 360, 600]],
          detail: "GLM Coding Plan peaks Mon-Fri 14:00-18:00 (UTC+8); off-peak usage is charged at 50% credits."
        },
        {
          provider: "ollama",
          model: /\Adeepseek-/,
          peak: [[WEEKDAYS, 720, 1080]],
          detail: "Ollama Cloud off-peak pricing applies outside Mon-Fri 12:00-18:00 UTC."
        },
        {
          provider: "opencode",
          model: /\Adeepseek-/,
          peak: [[WEEKDAYS, 60, 240], [WEEKDAYS, 360, 600]],
          detail: "DeepSeek peaks Mon-Fri 01:00-04:00 and 06:00-10:00 UTC; all other hours are off-peak."
        }
      ].freeze

      module_function

      def schedule_for(provider, model_id = nil)
        SCHEDULES.find do |schedule|
          next false unless schedule[:provider] == provider.to_s
          next true if schedule[:model].nil?

          schedule[:model].match?(model_id.to_s)
        end
      end

      def model_state(provider, model_id, now = Time.now.utc)
        schedule = schedule_for(provider, model_id)
        return nil unless schedule

        peak = peak_now?(schedule, now)
        {
          modelId: model_id.to_s,
          state: peak ? PEAK : OFF_PEAK,
          label: peak ? "Peak" : "Off-peak",
          detail: schedule[:detail]
        }
      end

      # Aggregate for a provider's known model ids. Every matching model shares
      # one schedule, so the result is uniform; nil means no model has a
      # time-of-day schedule (including a model-gated provider with no matching
      # model).
      def provider_state(provider, model_ids, now = Time.now.utc)
        ids = Array(model_ids).map(&:to_s).reject(&:empty?)
        schedule = schedule_for(provider)
        matching = if schedule.nil?
                     ids.select { |id| schedule_for(provider, id) }
                   elsif schedule[:model].nil?
                     ids.empty? ? [nil] : ids
                   else
                     ids.select { |id| schedule_for(provider, id) }
                   end
        return nil if matching.empty?

        state_for = model_state(provider, matching.first, now)
        return nil unless state_for

        {
          provider: provider.to_s,
          state: state_for[:state],
          label: state_for[:label],
          detail: state_for[:detail],
          models: matching.reject(&:nil?).filter_map { |id| model_state(provider, id, now) }
        }
      end

      def peak_now?(schedule, now)
        utc = now.utc
        minutes = (utc.hour * 60) + utc.min
        wday = utc.wday
        schedule[:peak].any? do |days, start_minute, end_minute|
          days.cover?(wday) && minutes >= start_minute && minutes < end_minute
        end
      end
    end
  end
end
