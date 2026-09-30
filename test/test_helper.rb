# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "time"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "tokenmaxx"

# Minitest 6 (the Ruby 4.0 default) removed minitest/mock and the
# Object#stub helper this suite was written against, so the stub-based tests
# error with NoMethodError before they run. Keep the upstream helper wherever
# the toolchain still ships it, and restore the scoped single-method form the
# tests use where it does not: stub a method for the duration of the block, call
# the replacement with the original arguments when it is callable, and put the
# original method back afterwards.
begin
  require "minitest/mock"
rescue LoadError
  nil
end

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

Object.include(MinitestStubCompat) unless Object.method_defined?(:stub)

module TokenMaxxTestHelpers
  def build_config
    TokenMaxx::Core::Config.normalize_config(TokenMaxx::Core::Config.default_config)
  end

  def with_provider_state(config, provider, **attrs)
    TokenMaxx::Core::Config.update_provider(config, provider) do |entry|
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
    Dir.mktmpdir("tokenmaxx-home") do |dir|
      previous = ENV["TOKENMAXX_HOME"]
      ENV["TOKENMAXX_HOME"] = dir
      yield dir
    ensure
      ENV["TOKENMAXX_HOME"] = previous
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
  include TokenMaxxTestHelpers
end

# Hermetic test home: config, state, and legacy-import paths derive from
# Dir.home, so without this the suite writes into (and now also migrates
# files out of) the real user state. Individual tests may re-scope
# ENV["HOME"] further; this only guarantees the run never starts at the
# real home.
TEST_HOME = Dir.mktmpdir("tokenmaxx-test-home")
ENV["HOME"] = TEST_HOME
Minitest.after_run { FileUtils.remove_entry(TEST_HOME) }
