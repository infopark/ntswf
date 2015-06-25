require "ntswf"
require "json"

describe Ntswf::Client do
  let(:default_config) do
    {
      activity_task_lists: {"test" => "atl"},
      decision_task_list: "dtl",
      unit: "test",
    }
  end
  let(:config) {default_config}

  let(:client) { Ntswf.create(:client, config) }
  before { allow(client).to receive :log }

  describe "starting an execution" do
    let(:execution) { AWS::SimpleWorkflow::WorkflowExecution.new("test", "workflow_id", "run_id") }

    before { allow_any_instance_of(AWS::SimpleWorkflow::WorkflowType).to receive_messages(start_execution: execution) }
    before { allow_any_instance_of(AWS::SimpleWorkflow::WorkflowExecution).to receive_messages(status: :open) }

    it "should use the master workflow type" do
      workflow_type = double.as_null_object
      expect(AWS::SimpleWorkflow::WorkflowType).to receive(:new).
          with(anything, 'master-workflow', 'v1').and_return workflow_type
      client.start_execution({})
      expect(workflow_type).to have_received :start_execution
    end

    describe "returned values" do
      before { expect_any_instance_of(AWS::SimpleWorkflow::WorkflowType).to receive(:start_execution) }

      subject do
        client.start_execution(
          execution_id: "the_id",
          name: :the_worker,
          params: {param: "test"},
        )
      end

      its([:run_id]) { should eq "run_id" }
      its([:params]) { should eq(param: "test") }
      its([:status]) { should eq :open }
      its([:name]) { should eq "the_worker" }
      its([:workflow_id]) { should eq "workflow_id" }
    end

    describe "passed workflow execution args" do
      subject do
        args = nil
        allow_any_instance_of(AWS::SimpleWorkflow::WorkflowType).to receive(:start_execution) do |type, options|
          args = options
          execution
        end
        client.start_execution(execution_id: "the_id", name: :the_worker, unit: "test")
        args
      end

      its([:tag_list]) { should eq(["test", "the_worker"]) }
      its([:workflow_id]) { should eq "test;the_id" }

      expected_args = [
        :child_policy,
        :execution_start_to_close_timeout,
        :input,
        :tag_list,
        :task_list,
        :task_start_to_close_timeout,
      ]
      expected_args.each do |expected_arg|
        its([expected_arg]) { should_not be_nil }
      end

      context "when configured with a service" do
        let(:config) {default_config.merge(execution_id_prefix: "cms")}

        its([:workflow_id]) { should eq "cms;the_id" }
      end
    end
  end

  describe "finding" do
    let(:mock_status) {:fantasyland}
    let(:execution) { AWS::SimpleWorkflow::WorkflowExecution.new(nil, "flow_id", "r1") }

    before { allow_any_instance_of(AWS::SimpleWorkflow::WorkflowExecution).to receive_messages(status: mock_status) }

    let(:event_started) do
      double("history_event: started", event_type: "WorkflowExecutionStarted", attributes:
          AWS::SimpleWorkflow::HistoryEvent::Attributes.new(nil,
            "input" => {name: :my_test, params: {"test" => "value"}}.to_json,
          ))
    end
    let(:event_completed) do
      double("history_event: completed", event_type: "WorkflowExecutionCompleted", attributes:
          AWS::SimpleWorkflow::HistoryEvent::Attributes.new(nil,
            "input" => {name: :my_test, params: {"test" => "value"}}.to_json,
            "result" => {"outcome" => "some result"}.to_json,
          ))
    end
    let(:event_failed) do
      double("history_event: failed", event_type: "WorkflowExecutionFailed", attributes:
          AWS::SimpleWorkflow::HistoryEvent::Attributes.new(nil,
            "details" => {error: "error message"}.to_json,
          ))
    end
    let(:event_exception) do
      double("history_event: exception", event_type: "WorkflowExecutionFailed", attributes:
          AWS::SimpleWorkflow::HistoryEvent::Attributes.new(nil,
            "details" => {exception: "TheExceptionClass", error: "error message"}.to_json,
          ))
    end
    let(:event_cancelled) do
      double("history_event: cancelled", event_type: "WorkflowExecutionCanceled")
    end

    subject do
      executions = AWS::SimpleWorkflow::WorkflowExecutionCollection.new(nil)
      expect(client.domain).to receive(:workflow_executions).and_return(executions)
      expect_any_instance_of(AWS::SimpleWorkflow::WorkflowExecutionCollection).to receive(:at).with(
          "flow_id", "some_run_id").and_return(execution)
      client.find(workflow_id: "flow_id", run_id: "some_run_id")
    end

    let(:expected) {{
      params: {"test" => "value"},
      run_id: "r1",
      status: mock_status,
      name: "my_test",
      workflow_id: "flow_id",
    }}

    describe "properties of" do
      let(:events) do
        instance_double(AWS::SimpleWorkflow::HistoryEventCollection,
          reverse_order: event_array.reverse,
          first: event_array.first,
          map: event_array.map,
        )
      end

      before { allow(execution).to receive_messages(history_events: events) }

      describe "old tasks for backwards compatibility" do
        let(:input) { ["legacy", [1, 2, 3]] }
        let(:event_array) do
          [
            instance_double(AWS::SimpleWorkflow::HistoryEvent,
              event_type: "WorkflowExecutionStarted",
              attributes:
                  AWS::SimpleWorkflow::HistoryEvent::Attributes.new(nil, "input" => input.to_json)
            )
          ]
        end

        its([:name]) { should eq "legacy" }
        its([:params]) { should eq [1, 2, 3] }
      end

      describe "an open task" do
        let(:event_array) { [event_started] }
        let(:mock_status) { :open }
        it { is_expected.to include expected }
      end

      describe "a completed task" do
        let(:mock_status) { :completed }

        context "with consistent history events" do
          let(:event_array) { [event_started, event_completed] }
          it { is_expected.to include(expected.merge(outcome: "some result")) }
        end

        context "with inconsistent history events" do
          let(:event_array) { [event_started] }
          it { is_expected.to eq(expected.merge(status: :open)) }
        end
      end

      describe "a failed task" do
        let(:event_array) { [event_started, event_failed] }
        it { is_expected.to include(expected.merge(error: "error message")) }
      end

      describe "an exception task" do
        let(:event_array) { [event_started, event_exception] }
        it { is_expected.to eq(expected.merge(exception: "TheExceptionClass", error: "error message")) }
      end

      describe "a cancelled task" do
        let(:event_array) { [event_started, event_cancelled] }
        it { is_expected.to eq(expected.merge(
            exception: "WorkflowExecutionCanceled", error: "WorkflowExecutionCanceled")) }
      end
    end
  end

  describe "#active?" do
    let(:workflow_id) { "flow_id" }
    let(:executions) { instance_double(AWS::SimpleWorkflow::WorkflowExecutionCollection) }

    subject { client.active?(workflow_id) }

    before do
      allow(client.domain).to receive(:workflow_executions).and_return(executions)
      allow(executions).to receive(:with_workflow_id).with(workflow_id) do
        allow(executions).to receive(:with_status).with(:open) do
          allow(executions).to receive(:first).and_return(execution)
          executions
        end
        executions
      end
    end

    context "when an execution of the workflow is active" do
      let(:execution) { instance_double(AWS::SimpleWorkflow::WorkflowExecution) }

      it { is_expected.to be true }
    end

    context "when no execution of the workflow is active" do
      let(:execution) { nil }

      it { is_expected.to be false }
    end
  end
end
