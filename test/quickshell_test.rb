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

  # A glyph concatenated into a label string inherits the text font, and Fira Code
  # has no Nerd Font codepoints — fontconfig then resolves each glyph on its own,
  # which rendered the settings codicon as a stray mark beside a History clock that
  # happened to land on the icon font. Draw the glyph as its own Text.
  def test_icon_glyphs_are_not_concatenated_into_text_font_strings
    qml = File.read(File.expand_path("../frontend/quickshell/shell.qml", __dir__))

    refute_match(
      /text:\s*[^\n]*(?:root\.glyphs\.\w+|control\.glyph|tab\.glyph)[^\n]*\+/,
      qml,
      "a glyph inside a label string is drawn in the text font, not the icon font"
    )
    assert_operator qml.scan("font.family: root.iconFont").length, :>=, 4,
                    "the tab, button, note and rail-title glyphs all need the icon font"
  end

  # The trailing peak marker sits at the end of a row whose right edge is the
  # card's content edge — where the detail view's scrollbar overlays the card's
  # padding. Everyone renders it through PeakGlyph, which owns the fixed slot and
  # the right inset; a raw glyph at a row's end is drawn flush against that edge.
  def test_peak_markers_render_through_the_slotted_component
    qml = File.read(File.expand_path("../frontend/quickshell/shell.qml", __dir__))

    component = qml[/component PeakGlyph: Text \{.*?\n    \}/m]

    refute_nil component, "peak markers need the PeakGlyph component"
    assert_includes component, "Layout.preferredWidth:"
    assert_includes component, "Layout.rightMargin:", "the marker must be inset from the card's content edge"
    assert_includes component, "text: root.peakBadgeIcon(peak)"
    refute_match(
      /text: root\.peakBadgeIcon\(modelData\.peak\)/,
      qml,
      "a raw glyph at a row's end is drawn flush against the card's content edge"
    )
    assert_equal 2, qml.scan(/^\s+PeakGlyph \{$/).length,
                 "the overview card row and the model local usage row both need the marker"
  end

  def test_peak_row_labels_can_shrink_below_their_text_width
    qml = File.read(File.expand_path("../frontend/quickshell/shell.qml", __dir__))

    rows = qml.scan(/Layout\.fillWidth: true\n\s+Layout\.minimumWidth: 0\n(?:\s+.*\n)*?\s+elide: Text\.ElideRight/)

    assert_equal 2, rows.length,
                 "the label before a peak marker must elide instead of pushing the marker off the row"
  end

  def test_running_pid_rejects_a_shell_command_that_only_mentions_the_qml_path
    config = build_config
    result = {
      stdout: "4321 /bin/zsh -c quickshell --path /installed/tokenmaxx/shell.qml\n",
      stderr: "",
      exitCode: 0
    }

    TokenMaxx::Runtime::QuickShell.stub(:resolve_shell_path, "/installed/tokenmaxx/shell.qml") do
      TokenMaxx::Runtime::QuickShell.stub(:resolve_quickshell_executable, "/usr/bin/quickshell") do
        TokenMaxx::Core::Process.stub(:run_command, result) do
          File.stub(:readlink, "/usr/bin/zsh") do
            assert_nil TokenMaxx::Runtime::QuickShell.running_pid(config)
          end
        end
      end
    end
  end

  def test_running_pid_accepts_the_quickshell_process_for_the_qml_path
    config = build_config
    result = {
      stdout: <<~OUTPUT,
        4321 /bin/zsh -c quickshell --path /installed/tokenmaxx/shell.qml
        9876 /usr/bin/quickshell --daemonize --path /installed/tokenmaxx/shell.qml
      OUTPUT
      stderr: "",
      exitCode: 0
    }
    executables = {
      "/proc/4321/exe" => "/usr/bin/zsh",
      "/proc/9876/exe" => "/usr/bin/quickshell"
    }

    TokenMaxx::Runtime::QuickShell.stub(:resolve_shell_path, "/installed/tokenmaxx/shell.qml") do
      TokenMaxx::Runtime::QuickShell.stub(:resolve_quickshell_executable, "/usr/bin/quickshell") do
        TokenMaxx::Core::Process.stub(:run_command, result) do
          File.stub(:readlink, ->(path) { executables.fetch(path) }) do
            assert_equal 9876, TokenMaxx::Runtime::QuickShell.running_pid(config)
          end
        end
      end
    end
  end
end
