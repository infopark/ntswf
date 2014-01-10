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
    # @option options [String] :execution_id Mandatory workflow ID suffix, allowed IDs are documented at docs.amazonwebservices.com (WorkflowId Property)
    # @option options [Numeric] :interval Optional, in seconds. Enforces periodic re-run of the task, even in case of failure
    # @option options [String] :name Identifies the kind of task for the executing unit
    # @option options [Hash] :params Custom task parameters passed on to the executing unit
    # @option options [String] :unit The executing unit's key, a corresponding activity task list must be configured
    # @option options [Numeric] :version Optional minimum version of the client. The task may be rescheduled by older clients.
    # @return [AWS::SimpleWorkflow::WorkflowExecution]
    # @raise [AWS::SimpleWorkflow::Errors::WorkflowExecutionAlreadyStartedFault]
    def start_execution(options)
      execution_id = options.delete(:execution_id)
      workflow_type.start_execution(
        child_policy: :terminate,
        execution_start_to_close_timeout: 48 * 3600,
        input: options.to_json,
        tag_list: [options[:unit].to_s, options[:name].to_s],
        task_list: decision_task_list,
        task_start_to_close_timeout: 10 * 60,
        workflow_id: [activity_task_list, execution_id].join(separator),
      )
    end

    # @return [String] separator part of the final *workflow_id*
    def separator
      ";"
    end

    protected

    def workflow_type
      @workflow_type ||= domain.workflow_types[workflow_name, workflow_version]
    end
  end
end