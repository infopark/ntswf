require_relative 'base'

module Ntswf
  module Worker
    include Ntswf::Base

    # *reason* value to force task reschedule, may be set if the worker is unable process the task
    RETRY = "Retry"

    # Run a method in a separate process.
    # This will ensure the call lives on if the master process is terminated.
    # If the *:subprocess_retries* configuration is set, {StandardError}s during the
    # method call will be retried accordingly.
    #
    # Exits the process if the *:pidfile* configuration is set and the PID file has been modified.
    def in_subprocess(method)
      raise_on_pidfile_change if @config.pidfile
      $stdout.sync = true
      if child = fork
        srand
        now = Time.now
        announce("#{method}: forked #{child} at #{now} (#{now.to_i})")
        Process.wait(child)
      else
        with_retry(@config.subprocess_retries || 0) { send method }
        exit!
      end
    end

    protected

    def with_retry(allowed_failures)
      yield
    rescue StandardError => e
      raise if allowed_failures.zero?
      allowed_failures -= 1
      log("retrying. exception raised: #{e.message}\n  #{e.backtrace.join("\n  ")}")
      retry
    end

    def raise_on_pidfile_change
      @pid ||= create_pidfile
      filed_pid = IO.read(@config.pidfile).strip rescue $!.message
      if filed_pid != Process.pid.to_s
        notify("I am a worker, and someone changed *my* PID file. I quit!",
          pid_file_content: filed_pid,
          pid_file: @config.pidfile,
          process_pid: Process.pid,
        )
        exit
      end
    end

    def create_pidfile
      IO.write(@config.pidfile, Process.pid)
    end

    private

    def poll_options
      options = {}
      if @config.identity_suffix
        options[:identity] = "#{Socket.gethostname}:#{Process.pid}:#{@config.identity_suffix}"
      end
      options
    end

  end
end