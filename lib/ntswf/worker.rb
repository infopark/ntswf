require_relative 'base'

module Ntswf
  module Worker
    include Ntswf::Base

    # *reason* value to force task reschedule, may be set if the worker is unable process the task
    RETRY = "Retry"

    # Run a method in a separate process.
    # This will ensure the call lives on if the master process is terminated.
    # If the *:subprocess_retries* configuration is set {StandardError}s during the
    # method call will be retried accordingly.
    def in_subprocess(method)
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
  end
end