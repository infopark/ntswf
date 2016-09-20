require "ntswf"
require "json"

describe Ntswf::Client do
  let(:default_config) do
    {
      activity_task_lists: {"test" => "atl"},
      decision_task_lists: {"test" => "dtl", "other" => "other-dtl"},
      unit: "test",
    }
  end
  let(:config) {default_config}

  let(:client) { Ntswf.create(:client, config) }
  before { allow(client).to receive :log }

  describe "starting an execution" do
    let(:execution) { AWS::SimpleWorkflow::WorkflowExecution.new("test", "workflow_id", "run_id") }
    let(:options) do
      {
        execution_id: "the_id",
        name: :the_worker,
        params: {param: "test"},
        unit: "test",
      }
    end

    subject(:start_execution) { client.start_execution(options) }

    before do
      allow_any_instance_of(AWS::SimpleWorkflow::WorkflowType).
          to receive_messages(start_execution: execution)
      allow_any_instance_of(AWS::SimpleWorkflow::WorkflowExecution).
          to receive_messages(status: :open)
    end

    it "should use the master workflow type" do
      workflow_type = double.as_null_object
      expect(AWS::SimpleWorkflow::WorkflowType).to receive(:new).
          with(anything, 'master-workflow', 'v1').and_return workflow_type
      start_execution
      expect(workflow_type).to have_received :start_execution
    end

    describe "returned values" do
      before do
        expect_any_instance_of(AWS::SimpleWorkflow::WorkflowType).to receive(:start_execution)
      end

      its([:run_id]) { should eq "run_id" }
      its([:params]) { should eq(param: "test") }
      its([:status]) { should eq :open }
      its([:name]) { should eq "the_worker" }
      its([:workflow_id]) { should eq "workflow_id" }

      context "when the execution failed extremely fast" do
        before do
          allow_any_instance_of(AWS::SimpleWorkflow::WorkflowExecution).
              to receive(:status).and_return(:failed)
        end

        its([:status]) { should eq :open }
      end
    end

    describe "passed workflow execution args" do
      subject(:passed_args) do
        args = nil
        allow_any_instance_of(AWS::SimpleWorkflow::WorkflowType).
            to receive(:start_execution) do |type, options|
              args = options
              execution
            end
        start_execution
        args
      end

      its([:tag_list]) { is_expected.to eq(["test", "the_worker"]) }
      its([:workflow_id]) { is_expected.to eq("test;the_id") }
      its([:task_list]) { is_expected.to eq("dtl") }

      expected_args = [
        :child_policy,
        :execution_start_to_close_timeout,
        :input,
        :task_start_to_close_timeout,
      ]
      expected_args.each do |expected_arg|
        its([expected_arg]) { is_expected.to_not be_nil }
      end

      context "when configured with a service" do
        let(:config) { default_config.merge(execution_id_prefix: "cms") }

        its([:workflow_id]) { is_expected.to eq("cms;the_id") }
      end

      context "with legacy config" do
        let(:config) do
          default_config.merge(decision_task_list: "legacy-dtl").tap do |c|
            c.delete(:decision_task_lists)
          end
        end

        its([:task_list]) { is_expected.to eq("legacy-dtl") }
      end

      context "when started for a different unit" do
        let(:options) { super().merge(unit: "other") }

        its([:task_list]) { is_expected.to eq("other-dtl") }

        context "with legacy config" do
          let(:config) do
            default_config.merge(decision_task_list: "legacy-dtl").tap do |c|
              c.delete(:decision_task_lists)
            end
          end

          its([:task_list]) { is_expected.to eq("legacy-dtl") }
        end
      end

      context "when started without explicitly specifying a unit" do
        let(:options) { super().tap {|o| o.delete(:unit) } }

        its([:task_list]) { is_expected.to eq("dtl") }
      end
    end

    context "when decision task list configuration is missing" do
      let(:config) { default_config.merge(decision_task_lists: {other: "foo"}) }

      context "for the (implicit) default unit" do
        let(:options) { super().tap {|o| o.delete(:unit) } }

        it "fails" do
          expect { start_execution }.to raise_error(
              Ntswf::Errors::InvalidArgument, /Missing decision task list.*'test'/)
        end
      end

      context "for an explicitly specified unit and the default unit (which is the fallback)" do
        let(:options) { super().merge(unit: "no_dtl") }

        it "fails" do
          expect { start_execution }.to raise_error(
              Ntswf::Errors::InvalidArgument, /Missing decision task list.*'no_dtl'/)
        end
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
end
