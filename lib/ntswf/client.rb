require_relative 'base'

module Ntswf
  # Interface for an application that wishes to start a task
  module Client
    include Ntswf::Base

    # Enqueue a new SWF task.
    #
    # The options configure the control flow of the task.
    # Excluding *:execution_id* they will be stored in the *input* argument of the task as JSON.
    # @param options [Hash] The task's options. Keys with special meaning:
    # @option options [String] :execution_id
    #   Mandatory workflow ID suffix, allowed IDs are documented at docs.amazonwebservices.com
    #   (WorkflowId Property)
    # @option options [Numeric] :interval
    #   Optional, in seconds. Enforces periodic start of
    #   new executions, even in case of failure
    # @option options [String] :name Identifies the kind of task for the executing unit
    # @option options [Hash] :params Custom task parameters passed on to the executing unit
    # @option options [String] :unit
    #   The executing unit's key, a corresponding activity task list must be configured
    # @option options [Numeric] :version
    #   Optional minimum version of the client. The task may be rescheduled by older clients.
    # @return (see #find)
    # @raise [AWS::SimpleWorkflow::Errors::WorkflowExecutionAlreadyStartedFault]
    def start_execution(options)
      workflow_execution = start_swf_workflow_execution(options)
      execution_details(workflow_execution).merge!(
        name: options[:name].to_s,
        params: options[:params],
      )
    end

    # Get status and details of a workflow execution.
    # @param ids [Hash] Identifies the queried execution
    # @option ids [String] :workflow_id Workflow ID
    # @option ids [String] :run_id Run ID
    # @raise [AWS::SimpleWorkflow::Errors::UnknownResourceFault]
    # @return [Hash]
    #   Execution properties.
    #   :exception:: Exception message for an unexpectedly failed execution
    #   :error:: Error message returned from an execution
    #   :outcome:: Result of a completed execution
    #   :params:: Custom params from JSON
    #   :run_id:: The workflow execution's run ID
    #   :status:: Calculated workflow execution status (:completed, :open, others indicating failure)
    #   :name:: Given task kind
    #   :workflow_id:: The workflow execution's workflow ID
    def find(ids)
      workflow_execution = domain.workflow_executions.at(ids[:workflow_id], ids[:run_id])
      history_details(workflow_execution)
    end

    protected

    def start_swf_workflow_execution(options)
      execution_id = options.delete(:execution_id)
      workflow_type.start_execution(
        child_policy: :terminate,
        execution_start_to_close_timeout: 48 * 3600,
        input: options.to_json,
        tag_list: [options[:unit].to_s, options[:name].to_s],
        task_list: decision_task_list,
        task_start_to_close_timeout: 10 * 60,
        workflow_id: workflow_id(execution_id_prefix, execution_id),
      )
    end

    def workflow_id(prefix, suffix)
      [prefix, suffix].join(separator)
    end

    def execution_details(workflow_execution)
      {
        workflow_id: workflow_execution.workflow_id,
        run_id: workflow_execution.run_id,
        status: workflow_execution.status,
      }
    end

    def history_details(workflow_execution)
      result = execution_details(workflow_execution)
      input = parse_input workflow_execution.history_events.first.attributes.input
      result.merge!(name: input["name"].to_s, params: input["params"])

      case result[:status]
      when :open
        # nothing
      when :completed
        result.merge!(completion_details workflow_execution)
      else
        result.merge!(failure_details workflow_execution)
      end
      result
    end

    def completion_details(workflow_execution)
      completed_event = workflow_execution.history_events.reverse_order.detect do |e|
        e.event_type == "WorkflowExecutionCompleted"
      end
      if completed_event
        {outcome: parse_attribute(completed_event, :result)["outcome"]}
      else
        {status: :open}
      end
    end

    TERMINAL_EVENT_TYPES_ON_FAILURE = %w(
      WorkflowExecutionFailed
      WorkflowExecutionTimedOut
      WorkflowExecutionCanceled
      WorkflowExecutionTerminated
    )

    def failure_details(workflow_execution)
      terminal_event = workflow_execution.history_events.reverse_order.detect {|e|
        TERMINAL_EVENT_TYPES_ON_FAILURE.include?(e.event_type)
      }
      if terminal_event
        event_type = terminal_event.event_type
        case event_type
        when "WorkflowExecutionFailed"
          details = parse_attribute(terminal_event, :details)
          {
            error: details["error"],
            exception: details["exception"],
          }
        else
          {
            error: event_type,
            exception: event_type,
          }
        end
      else
        log("No terminal event for execution"\
            " #{workflow_execution.workflow_id} | #{workflow_execution.run_id}."\
            " Event types: #{workflow_execution.history_events.map(&:event_type)}") rescue nil
        {
          error: "Execution has finished with status #{workflow_execution.status},"\
              " but did not provide details."
        }
      end
    end

    def parse_attribute(event, key)
      value = nil
      begin
        json_value = event.attributes[key]
      rescue ArgumentError
        # missing key in event attributes
      end
      if json_value
        begin
          value = JSON.parse json_value
        rescue # JSON::ParserError, ...
          # no JSON
        end
      end
      value = nil unless value.kind_of? Hash
      value || {}
    end

    def workflow_type
      @workflow_type ||= domain.workflow_types[workflow_name, workflow_version]
    end
  end
end