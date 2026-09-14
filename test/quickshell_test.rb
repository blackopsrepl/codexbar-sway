# frozen_string_literal: true

require_relative "test_helper"

class QuickShellTest < Minitest::Test
  def test_ui_adapter_only_writes_ui_state_on_explicit_actions
    qml = File.read(File.expand_path("../frontend/quickshell/shell.qml", __dir__))

    refute_match(
      /onAdapterUpdated\s*:\s*writeAdapter\(\)/,
      qml,
      "Rewriting ui.json on every adapter update clobbers the daemon-written open state"
    )
    assert_operator(
      qml.scan("writeAdapter()").length, :>=, 2,
      "Closing the panel and focusing a provider must still persist ui.json"
    )
  end

  def test_running_pid_rejects_a_shell_command_that_only_mentions_the_qml_path
    config = build_config
    result = {
      stdout: "4321 /bin/zsh -c quickshell --path /installed/codexbar/shell.qml\n",
      stderr: "",
      exitCode: 0
    }

    CodexBar::Runtime::QuickShell.stub(:resolve_shell_path, "/installed/codexbar/shell.qml") do
      CodexBar::Runtime::QuickShell.stub(:resolve_quickshell_executable, "/usr/bin/quickshell") do
        CodexBar::Core::Process.stub(:run_command, result) do
          File.stub(:readlink, "/usr/bin/zsh") do
            assert_nil CodexBar::Runtime::QuickShell.running_pid(config)
          end
        end
      end
    end
  end

  def test_running_pid_accepts_the_quickshell_process_for_the_qml_path
    config = build_config
    result = {
      stdout: <<~OUTPUT,
        4321 /bin/zsh -c quickshell --path /installed/codexbar/shell.qml
        9876 /usr/bin/quickshell --daemonize --path /installed/codexbar/shell.qml
      OUTPUT
      stderr: "",
      exitCode: 0
    }
    executables = {
      "/proc/4321/exe" => "/usr/bin/zsh",
      "/proc/9876/exe" => "/usr/bin/quickshell"
    }

    CodexBar::Runtime::QuickShell.stub(:resolve_shell_path, "/installed/codexbar/shell.qml") do
      CodexBar::Runtime::QuickShell.stub(:resolve_quickshell_executable, "/usr/bin/quickshell") do
        CodexBar::Core::Process.stub(:run_command, result) do
          File.stub(:readlink, ->(path) { executables.fetch(path) }) do
            assert_equal 9876, CodexBar::Runtime::QuickShell.running_pid(config)
          end
        end
      end
    end
  end
end
