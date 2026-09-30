# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"

class ProcessTest < Minitest::Test
  def test_drains_large_stdout_and_stderr_while_child_is_running
    size = 262_144
    result = TokenMaxx::Core::Process.run_command(
      RbConfig.ruby,
      ["-e", "STDOUT.write('x' * #{size}); STDERR.write('y' * #{size})"],
      timeout_ms: 2000
    )

    assert_equal 0, result[:exitCode]
    assert_equal "x" * size, result[:stdout]
    assert_equal "y" * size, result[:stderr]
  end
end
