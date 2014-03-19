require 'aws'
require 'ostruct'
require 'securerandom'

module Ntswf
  module Base
    # @param config [Hash] A configuration with the following keys:
    # @option config [String] :access_key_id AWS credential
    # @option config [Hash] :activity_task_lists
    #   The task list names for activities as hash (see also *:unit*)
    # @option config [String] :decision_task_list The task list name for decisions
    # @option config [String] :domain The SWF domain name
    # @option config [Numeric] :execution_version
    #   Value allowing clients to reject future execution versions
    # @option config [String] :execution_id_prefix
    #   Prefix for {Client Client's} execution id (same restrictions for value)
    #   (defaults to value of *:unit*)
    # @option config [String] :pidfile
    #   A path receiving the current PID for looping methods. Causes exit, if
    #   overwritten by another process. See {Worker#in_subprocess}
    # @option config [Numeric] :subprocess_retries (0) see {Worker#in_subprocess}
    # @option config [String] :secret_access_key AWS credential
    # @option config [String] :task_list_suffix_file
    #   Development option.
    #   A random ID is stored at the given path, and appended to all task list names.
    # @option config [String] :unit This worker/client's activity task list key
    # @raise If a task list name is invalid
    def configure(config)
      @config = OpenStruct.new(config)
      autocomplete_task_list_names!
      raise_if_invalid_task_list
    end

    # Configure a proc or block to be called on handled errors
    # @yieldparam error [Hash]
    #   Description of the error:
    #   :message:: The error message or the exception
    #   :params:: Error details
    # @param proc [Proc] The callback
    def on_notify(proc = nil, &block)
      @notify_callback = proc || block
    end

    # @return [AWS::SimpleWorkflow]
    def swf
      @swf ||= AWS::SimpleWorkflow.new(access_key_id: @config.access_key_id,
          secret_access_key: @config.secret_access_key, use_ssl: true)
    end

    def workflow_name
      "#{service}-workflow"
    end

    def workflow_version
      "v1"
    end

    def domain
      @domain ||= swf.domains[@config.domain]
    end

    def activity_task_lists
      @config.activity_task_lists
    end

    def decision_task_list
      @config.decision_task_list or raise "Missing decision task list configuration"
    end

    def activity_task_list
      activity_task_lists[default_unit] or
          raise "Missing activity task list configuration for default unit '#{default_unit}'"
    end

    def default_unit
      @default_unit ||= @config.unit.to_s
    end

    def service
      (@config.execution_id_prefix || default_unit).to_s
    end

    def execution_version
      @config.execution_version
    end

    # Parse the options stored in a task's *input* value
    # @param input [String] A task's input
    # @return [Hash] Input, converted back from JSON
    # @see Ntswf::Client#start_execution Hash keys to be expected
    def parse_input(input)
      options, legacy_params = JSON.parse(input)
      options = {"name" => options} unless options.kind_of? Hash
      options.merge!("params" => legacy_params) if legacy_params
      options
    end

    def notify(message, params)
      log("#{message.message}\n  #{message.backtrace.join("\n  ")}") if message.kind_of? Exception
      @notify_callback.call(message: message, params: params) if @notify_callback
    end

    # @return [String] separator for composite *workflow_id*
    def separator
      ";"
    end

    def activity_type
      @activity_type ||= domain.activity_types[activity_name, workflow_version]
    end

    protected

    def activity_name
      "#{service}-activity"
    end

    def announce(s)
      $0 = s
      log(s)
    end

    def log(s)
      $stdout.puts("#{Process.pid} #{s}")
    end

    def raise_if_invalid_task_list
      atl_values = activity_task_lists.values if activity_task_lists
      [*atl_values, *@config.decision_task_list].each do |task_list|
        if task_list.include?(separator)
          raise "Invalid config '#{task_list}': Separator '#{separator}' is reserved for internal use."
        end
        if task_list.count(". ") > 0
          raise "Invalid config '#{task_list}': Dots and spaces not allowed."
        end
      end
    end

    def autocomplete_task_list_names!
      @config.decision_task_list = autocomplete(@config.decision_task_list, "master-dtl")
      if @config.activity_task_lists
        @config.activity_task_lists.each do |key, value|
          @config.activity_task_lists[key] = autocomplete(value, "#{key}-atl")
        end
      end
    end

    def autocomplete(value, fallback)
      value = fallback unless value.kind_of? String
      "#{value}#{task_list_suffix}"
    end

    def task_list_suffix
      file = @config.task_list_suffix_file
      return "" unless file
      File.write(file, SecureRandom.hex(9)) unless File.exist?(file)
      @suffix ||= File.read(file)
    end
  end
end