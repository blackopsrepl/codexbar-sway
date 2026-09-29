# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "time"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "codexbar"

# Minitest 6 (the Ruby 4.0 default) removed minitest/mock and the
# Object#stub helper this suite was written against. Restore the scoped
# single-method form the tests use: stub a method for the duration of the
# block, call the replacement with the original arguments when it is
# callable, and put the original method back afterwards.
module MinitestStubCompat
  def stub(name, value_or_callable)
    original = method(name)
    define_singleton_method(name) do |*arguments, **keywords, &block|
      if value_or_callable.respond_to?(:call)
        value_or_callable.call(*arguments, **keywords, &block)
      else
        value_or_callable
      end
    end
    yield
  ensure
    define_singleton_method(name, original)
  end
end

Object.include(MinitestStubCompat)

module CodexBarTestHelpers
  def build_config
    CodexBar::Core::Config.normalize_config(CodexBar::Core::Config.default_config)
  end

  def with_provider_state(config, provider, **attrs)
    CodexBar::Core::Config.update_provider(config, provider) do |entry|
      attrs.each do |key, value|
        entry[key] = value
      end
    end
  end

  def window(used_percent:, window_minutes:, now:, resets_in_minutes:)
    {
      usedPercent: used_percent,
      windowMinutes: window_minutes,
      resetsAt: (now + (resets_in_minutes * 60)).utc.iso8601,
      resetDescription: nil
    }
  end

  def usage_payload(provider:, now:, primary: nil, secondary: nil, tertiary: nil, meters: nil, identity: nil, spend: nil, provider_cost: nil)
    {
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      meters: meters,
      updatedAt: now.utc.iso8601,
      identity: identity || {
        providerID: provider,
        accountEmail: "#{provider}@example.com",
        loginMethod: "spec"
      },
      spend: spend,
      providerCost: provider_cost
    }.compact
  end

  def provider_result(provider:, usage: nil, error: nil, notes: [], incident: nil, credits: nil, source: "spec")
    {
      provider: provider,
      source: source,
      usage: usage,
      error: error,
      notes: notes,
      incident: incident,
      credits: credits
    }.compact
  end

  def with_temp_home
    Dir.mktmpdir("codexbar-home") do |dir|
      previous = ENV["CODEXBAR_HOME"]
      ENV["CODEXBAR_HOME"] = dir
      yield dir
    ensure
      ENV["CODEXBAR_HOME"] = previous
    end
  end

  def write_jsonl(path, records)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")
  end

  def capture_stdout
    original = $stdout
    output = StringIO.new
    $stdout = output
    yield
    output.string
  ensure
    $stdout = original
  end

  def capture_stderr
    original = $stderr
    output = StringIO.new
    $stderr = output
    yield
    output.string
  ensure
    $stderr = original
  end
end

class Minitest::Test
  include CodexBarTestHelpers
end
