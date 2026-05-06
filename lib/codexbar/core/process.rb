# frozen_string_literal: true

require "open3"
require "shellwords"

module CodexBar
  module Core
    module Process
      module_function

      def run_command(command, args = [], cwd: nil, env: nil, stdin: nil, timeout_ms: nil)
        stdout = +""
        stderr = +""
        exit_code = 1
        options = {}
        options[:chdir] = cwd if cwd

        Open3.popen3(env || {}, command, *args, **options) do |input, output, error, wait_thread|
          input.write(stdin) if stdin
          input.close

          if timeout_ms
            deadline = Time.now + (timeout_ms / 1000.0)
            until wait_thread.join(0.05)
              if Time.now >= deadline
                ::Process.kill("TERM", wait_thread.pid)
                raise "Command timed out after #{timeout_ms}ms: #{command}"
              end
            end
          end

          stdout = output.read
          stderr = error.read
          exit_code = wait_thread.value.exitstatus || 1
        end

        { stdout: stdout, stderr: stderr, exitCode: exit_code }
      end

      def spawn_detached_shell(command)
        pid = ::Process.spawn("sh", "-lc", command, out: File::NULL, err: File::NULL)
        ::Process.detach(pid)
        pid
      end

      def spawn_detached(command, args = [], env: nil, cwd: nil, out: File::NULL, err: File::NULL)
        options = { out: out, err: err }
        options[:chdir] = cwd if cwd
        pid = ::Process.spawn(env || {}, command, *args, **options)
        ::Process.detach(pid)
        pid
      end

      def executable_path(command)
        candidate = command.to_s.strip
        return nil if candidate.empty?
        return File.expand_path(candidate) if candidate.include?(File::SEPARATOR) && File.executable?(candidate)

        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
          path = File.join(directory, candidate)
          return path if File.executable?(path) && !File.directory?(path)
        end

        nil
      end

      def process_alive?(pid)
        return false unless pid.to_i.positive?

        ::Process.kill(0, pid.to_i)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def open_url(url)
        target = url.to_s.strip
        return nil if target.empty?

        spawn_detached_shell("xdg-open #{Shellwords.escape(target)} >/dev/null 2>&1")
      end
    end
  end
end
