require_relative 'worker'

module Ntswf
  # Interface for a worker arbitrating tasks, optionally for multiple apps
  module DecisionWorker
    include Ntswf::Worker

    # Start the worker loop for decision tasks.
    def process_decisions
      loop { in_subprocess :process_decision_task }
    end

    # Process a decision task.
    # The following task values are interpreted:
    # input:: see {Ntswf::Client#start_execution}
    # reason:: reschedule if {RETRY}
    # result:: Interpreted as {Hash}, see below for keys
    # Result keys
    # :seconds_until_retry:: See {ActivityWorker#on_activity}
    def process_decision_task
      announce("polling for decision task #{decision_task_list}")
      domain.decision_tasks.poll_for_single_task(decision_task_list, poll_options) do |task|
        announce("got decision task #{task.workflow_execution.inspect}")
        begin
          task.new_events.each { |event| process_decision_event(task, event) }
        rescue => e
          notify(e, workflow_execution: task.workflow_execution.inspect)
          raise e
        end
      end
    end

    protected

    def process_decision_event(task, event)
      log("processing event #{event.inspect}")
      case event.event_type
      when 'WorkflowExecutionStarted' then schedule(task, event)
      when 'TimerFired' then retry_or_continue_as_new(task, event)
      when 'ActivityTaskCompleted' then activity_task_completed(task, event)
      when 'ActivityTaskFailed' then activity_task_failed(task, event)
      when 'ActivityTaskTimedOut' then activity_task_timed_out(task, event)
      end
    end

    def activity_task_completed(task, event)
      result = parse_result(event.attributes.result)
      start_timer(task, result) or task.complete_workflow_execution(result: event.attributes.result)
    end

    def activity_task_failed(task, event)
      if (event.attributes.reason == RETRY)
        schedule(task, task.events.first)
      else
        start_timer(task) or task.fail_workflow_execution(
            event.attributes.to_h.keep_if {|k| [:details, :reason].include? k})
      end
    end

    def activity_task_timed_out(task, event)
      notify("Timeout in Simple Workflow. Possible cause: all workers busy",
          workflow_execution: task.workflow_execution.inspect)
      start_timer(task) or task.cancel_workflow_execution(details: 'activity task timeout')
    end

    def start_timer(task, result = {})
      interval = result["seconds_until_retry"] || result["seconds_until_restart"]
      unless interval
        options = parse_input(task.events.first.attributes.input)
        interval = options['interval']
      end
      task.start_timer(interval.to_i, control: result.to_json) if interval
      interval
    end

    def retry_or_continue_as_new(task, event)
      original_event = task.events.first
      if to_be_continued?(task, event)
        keys = [
          :child_policy,
          :execution_start_to_close_timeout,
          :input,
          :tag_list,
          :task_list,
          :task_start_to_close_timeout,
        ]
        attributes = original_event.attributes.to_h.keep_if {|k| keys.include? k}
        task.continue_as_new_workflow_execution(attributes)
      else
        schedule(task, original_event)
      end
    end

    def schedule(task, data_providing_event)
      input = data_providing_event.attributes.input
      options = parse_input(input)
      app_in_charge = options['unit'] || guess_app_from(data_providing_event)
      activity_group = options['activity_group'] || self.activity_group
      task_list = activity_group_list(activity_task_lists[app_in_charge], activity_group)
      raise Errors::InvalidArgument.new(
          "Missing activity task list config for #{app_in_charge.inspect}") unless task_list

      task.schedule_activity_task(activity_type, {
        heartbeat_timeout: :none,
        input: input,
        task_list: task_list,
        schedule_to_close_timeout: 12 * 3600,
        schedule_to_start_timeout: 10 * 60,
        start_to_close_timeout: 12 * 3600,
      })
    end

    def parse_result(result)
      if result
        value = JSON.parse(result) rescue nil # expecting JSON::ParserError
      end
      value = {} unless value.kind_of? Hash
      value
    end

    private

    def to_be_continued?(task, event)
      options = parse_input(task.events.first.attributes.input)
      return true if options["interval"]
      started_event = task.events.find { |e| e.event_id == event.attributes.started_event_id }
      result = parse_result(started_event.attributes.to_h[:control])
      result["seconds_until_restart"] || result["perform_again"]
    end

    # transitional, until all apps speak the input options protocol
    def guess_app_from(data_providing_event)
      data_providing_event.workflow_execution.workflow_type.name[/\w+/]
    end
  end
end
