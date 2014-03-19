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
  before { client.stub :log }

  describe "starting an execution" do
    let(:execution) { AWS::SimpleWorkflow::WorkflowExecution.new("test", "workflow_id", "run_id") }

    before { AWS::SimpleWorkflow::WorkflowType.any_instance.stub(start_execution: execution) }
    before { AWS::SimpleWorkflow::WorkflowExecution.any_instance.stub(status: :open) }

    describe "returned values" do
      before { AWS::SimpleWorkflow::WorkflowType.any_instance.should_receive(:start_execution) }

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
        AWS::SimpleWorkflow::WorkflowType.any_instance.stub(:start_execution).with do |a|
          args = a
        end.and_return(execution)
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

    before { AWS::SimpleWorkflow::WorkflowExecution.any_instance.stub(status: mock_status) }

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
      client.domain.should_receive(:workflow_executions).and_return(executions)
      AWS::SimpleWorkflow::WorkflowExecutionCollection.any_instance.should_receive(:at).with(
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
      before do
        execution.stub(history_events: events)
        events.stub(reverse_order: events.reverse)
      end

      describe "old tasks for backwards compatibility" do
        let(:input) { ["legacy", [1, 2, 3]] }
        let(:events) do
          [
            double(event_type: "WorkflowExecutionStarted", attributes:
                AWS::SimpleWorkflow::HistoryEvent::Attributes.new(nil, "input" => input.to_json))
          ]
        end

        its([:name]) { should eq "legacy" }
        its([:params]) { should eq [1, 2, 3] }
      end

      describe "an open task" do
        let(:events) { [event_started] }
        let(:mock_status) { :open }
        it { should include expected }
      end

      describe "a completed task" do
        let(:mock_status) { :completed }

        context "with consistent history events" do
          let(:events) { [event_started, event_completed] }
          it { should include(expected.merge(outcome: "some result")) }
        end

        context "with inconsistent history events" do
          let(:events) { [event_started] }
          it { should eq(expected.merge(status: :open)) }
        end
      end

      describe "a failed task" do
        let(:events) { [event_started, event_failed] }
        it { should include(expected.merge(error: "error message")) }
      end

      describe "an exception task" do
        let(:events) { [event_started, event_exception] }
        it { should eq(expected.merge(exception: "TheExceptionClass", error: "error message")) }
      end

      describe "a cancelled task" do
        let(:events) { [event_started, event_cancelled] }
        it { should eq(expected.merge(
            exception: "WorkflowExecutionCanceled", error: "WorkflowExecutionCanceled")) }
      end
    end
  end
end
