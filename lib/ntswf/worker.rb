require_relative 'base'

module Ntswf
  module Worker
    include Ntswf::Base

    # *reason* value to force task reschedule, may be set if the worker is unable process the task
    RETRY = "Retry"
  end
end