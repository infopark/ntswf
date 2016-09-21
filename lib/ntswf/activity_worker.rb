require_relative 'worker'

module Ntswf
  # Interface for a worker executing tasks
  module ActivityWorker
    include Ntswf::Worker

    # Configure a proc or block to be called on receiving an {AWS::SimpleWorkflow::ActivityTask}
    # @yieldparam task [Hash]
    #   Description of the task's properties:
    #   :activity_task:: The {AWS::SimpleWorkflow::ActivityTask}
    #   :name:: Kind of task
    #   :params:: Custom parameters given to the execution (parsed back from JSON)
    #   :run_id:: The workflow execution's run ID
    #   :version:: Client version
    #   :workflow_id:: The workflow execution's workflow ID
    #
    #   See {Ntswf::Client#start_execution}'s options for details
    # @param proc [Proc] The callback
    # @yieldreturn [Hash]
    #   Processing result. The following keys are interpreted accordingly:
    #   :error:: Fails the task with the given error details.
    #   :outcome:: Completes the task, storing the outcome's value (as JSON).
    #   :seconds_until_restart::
    #     Starts the task as new, after the given delay.
    #   :seconds_until_retry::
    #     Re-schedules the task, after the given delay.
    #     In combination with an *:error*: Marks the task for immediate re-scheduling,
    #     ignoring the value.
    #     Please note that the behaviour is undefined if an *:interval* option has been set.
    def on_activity(proc = nil, &block)
      @task_callback = proc || block
    end

    # Start the worker loop for activity tasks.
    def process_activities
      loop { in_subprocess :process_activity_task }
    end

    def process_activity_task
      announce("polling for activity task #{activity_task_list}")
      domain.activity_tasks.poll_for_single_task(activity_task_list, poll_options) do |task|
        announce("got activity task #{task.activity_type.inspect} #{task.input}")
        process_single_task(task)
      end
    end

    protected

    def process_single_task(activity_task)
      returned_hash = @task_callback.call(describe(activity_task)) if @task_callback
      process_returned_hash(activity_task, returned_hash)
    rescue => exception
      fail_with_exception(activity_task, exception)
    end

    def fail_with_exception(activity_task, exception)
      notify(exception, activity_type: activity_task.activity_type.inspect,
          input: activity_task.input)
      details = {
        error: exception.message[0, 1000],
        exception: exception.class.to_s[0, 1000],
      }
      activity_task.fail!(details: details.to_json, reason: 'Exception')
    end

    def describe(activity_task)
      options = parse_input(activity_task.input)
      options.merge!(
        activity_task: activity_task,
        run_id: activity_task.workflow_execution.run_id,
        workflow_id: activity_task.workflow_execution.workflow_id,
      )
      options.map { |k, v| {k.to_sym => v} }.reduce(&:merge!)
    end

    KNOWN_RETURN_KEYS = [:error, :outcome, :seconds_until_retry]

    def process_returned_hash(activity_task, returned_hash)
      return unless returned_hash.kind_of? Hash
      kind, value = returned_hash.detect { |k, v| KNOWN_RETURN_KEYS.include? k }
      case kind
      when :error
        reason = returned_hash[:seconds_until_retry] ? "Retry" : "Error"
        activity_task.fail!(details: {error: value.to_s[0, 1000]}.to_json, reason: reason)
      when :outcome, :seconds_until_retry
        activity_task.complete!(result: returned_hash.to_json)
      end
    end
  end
end
