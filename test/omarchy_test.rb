# frozen_string_literal: true

require_relative "test_helper"

require "shellwords"

class OmarchyTest < Minitest::Test
  def setup
    @omarchy_path = Dir.mktmpdir
    @old_omarchy_path = ENV["OMARCHY_PATH"]
    ENV["OMARCHY_PATH"] = @omarchy_path
    @old_home = ENV["HOME"]
    ENV["HOME"] = Dir.mktmpdir
    write_defaults
  end

  def teardown
    tmp_home = ENV["HOME"]
    ENV["HOME"] = @old_home
    if @old_omarchy_path.nil?
      ENV.delete("OMARCHY_PATH")
    else
      ENV["OMARCHY_PATH"] = @old_omarchy_path
    end
    FileUtils.remove_entry(@omarchy_path) if File.directory?(@omarchy_path)
    FileUtils.remove_entry(tmp_home) if File.directory?(tmp_home)
    FileUtils.remove_entry(@fake_bin_dir) if @fake_bin_dir && File.directory?(@fake_bin_dir)
  end

  def test_install_seeds_user_config_from_defaults_after_weather
    result = CodexBar::Runtime::Omarchy.install(bin: fake_bin)

    assert result[:installed]
    assert_equal "defaults", result[:seededFrom]
    assert_equal "center", result[:section]
    assert_equal 2, result[:index]

    center = read_user_shell.dig("bar", "layout", "center")
    assert_equal %w[omarchy.clock omarchy.weather codexbar omarchy.system-update], ids(center)
  end

  def test_install_is_idempotent_and_updates_entry
    CodexBar::Runtime::Omarchy.install(bin: fake_bin)
    CodexBar::Runtime::Omarchy.install(bin: fake_bin, interval: 30)

    center = read_user_shell.dig("bar", "layout", "center")
    assert_equal 1, ids(center).count("codexbar")
    assert_equal 30, center.find { |item| item["id"] == "codexbar" }["interval"]
  end

  def test_install_honors_explicit_section_and_index
    result = CodexBar::Runtime::Omarchy.install(bin: fake_bin, section: "right", index: 1)

    assert_equal "right", result[:section]
    assert_equal 1, result[:index]
    right = read_user_shell.dig("bar", "layout", "right")
    assert_equal %w[omarchy.tray codexbar], ids(right)
  end

  def test_install_falls_back_to_center_end_for_unknown_anchor
    result = CodexBar::Runtime::Omarchy.install(bin: fake_bin, after: "omarchy.does-not-exist")

    assert result[:fallback]
    assert_equal "codexbar", ids(read_user_shell.dig("bar", "layout", "center")).last
  end

  def test_install_quotes_exec_paths_with_spaces
    @fake_bin_dir = Dir.mktmpdir
    spaced = File.join(@fake_bin_dir, "my tools")
    FileUtils.mkdir_p(spaced)
    bin = File.join(spaced, "codexbar")
    File.write(bin, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, bin)

    CodexBar::Runtime::Omarchy.install(bin: bin)

    entry = module_entry
    escaped = Shellwords.escape(bin)
    assert_equal("#{escaped} waybar render", entry["exec"])
    assert_equal("#{escaped} panel", entry["onClick"])
    assert_equal("#{escaped} refresh", entry["onMiddleClick"])
  end

  def test_install_rejects_unknown_binary
    error = assert_raises(RuntimeError) { CodexBar::Runtime::Omarchy.install(bin: "/nonexistent/codexbar") }
    assert_match(/not found or not executable/, error.message)
  end

  def test_remove_drops_module_and_keeps_neighbors
    CodexBar::Runtime::Omarchy.install(bin: fake_bin)

    result = CodexBar::Runtime::Omarchy.remove

    assert result[:removed]
    center = read_user_shell.dig("bar", "layout", "center")
    assert_equal %w[omarchy.clock omarchy.weather omarchy.system-update], ids(center)
  end

  def test_remove_without_install_reports_not_installed
    write_user_shell(default_shell)

    result = CodexBar::Runtime::Omarchy.remove

    refute result[:removed]
    assert_equal "module not installed", result[:reason]
  end

  def test_status_reflects_install_state
    refute CodexBar::Runtime::Omarchy.status[:installed]

    CodexBar::Runtime::Omarchy.install(bin: fake_bin)
    status = CodexBar::Runtime::Omarchy.status

    assert status[:installed]
    assert_equal "center", status[:section]
    assert_equal "codexbar", status[:entry]["id"]
    assert_equal "command", status[:entry]["type"]
  end

  def test_install_preserves_other_user_config_keys
    write_user_shell("custom" => { "note" => "keep me" })

    CodexBar::Runtime::Omarchy.install(bin: fake_bin)

    assert_equal({ "note" => "keep me" }, read_user_shell["custom"])
  end

  private

  def ids(entries)
    entries.map { |item| item["id"] }
  end

  def read_user_shell
    JSON.parse(File.read(CodexBar::Runtime::Omarchy.shell_config_path))
  end

  def module_entry
    read_user_shell.dig("bar", "layout", "center").find { |item| item["id"] == "codexbar" }
  end

  def write_user_shell(document)
    path = CodexBar::Runtime::Omarchy.shell_config_path
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(document))
  end

  def write_defaults
    path = File.join(@omarchy_path, "config", "omarchy", "shell.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(default_shell))
  end

  def default_shell
    {
      version: 1,
      bar: {
        position: "top",
        layout: {
          left: [{ id: "omarchy.workspaces" }],
          center: [
            { id: "omarchy.clock" },
            { id: "omarchy.weather" },
            { id: "omarchy.system-update" }
          ],
          right: [{ id: "omarchy.tray" }]
        }
      },
      plugins: []
    }
  end

  def fake_bin
    @fake_bin_dir = Dir.mktmpdir
    path = File.join(@fake_bin_dir, "codexbar")
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, path)
    path
  end
end
