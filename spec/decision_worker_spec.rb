require "ntswf"
require "json"

describe Ntswf::DecisionWorker do
  let(:atl_config) { { "test" => "atl" } }
  let(:dtl_config) { "dtl" }
  let(:unit) { "testt" }
  let(:config) { { unit: unit, decision_task_list: dtl_config, activity_task_lists: atl_config } }
  let(:worker) { Ntswf.create(:decision_worker, config) }

  let(:options) { {} }
  let(:input) { options.merge('params' => {'test' => 'value'}).to_json }
  let(:reason) { nil }
  let(:result) { nil }
  let(:attributes_hash) { { input: input, reason: reason, result: result } }
  let(:attributes) { double("Attributes", attributes_hash.merge(to_h: attributes_hash)) }
  let(:workflow_execution) { double("Workflow Execution", workflow_type: double(name: 'test-wf')) }
  let(:event) do
    double("Event", attributes: attributes, event_id: 1, event_type: event_type, workflow_execution:
        workflow_execution)
  end
  let(:events) { [event] }
  let(:task) { double("Task", new_events: [event], events: events).as_null_object }

  before { worker.stub(announce: nil, log: nil) }

  describe "processing a decision task" do
    it "should only query for the configured task list" do
      AWS::SimpleWorkflow::DecisionTaskCollection.any_instance.
          should_receive(:poll_for_single_task).with("dtl")
      worker.process_decision_task
    end

    describe "handling event" do
      before do
        AWS::SimpleWorkflow::DecisionTaskCollection.any_instance.stub(
            :poll_for_single_task).and_yield(task)
      end

      describe "ActivityTaskTimedOut" do
        let(:event_type) {"ActivityTaskTimedOut"}

        it "should cancel the execution" do
          task.should_receive :cancel_workflow_execution
          worker.process_decision_task
        end

        it "should notify" do
          worker.should_receive :notify
          worker.process_decision_task
        end
      end

      describe "ActivityTaskCompleted" do
        let(:event_type) {"ActivityTaskCompleted"}

        context "when requesting re-execution per seconds_until_retry" do
          let(:result) { {seconds_until_retry: 321}.to_json }

          it "schedules a timer event" do
            task.should_receive(:start_timer).with(321, anything)
            worker.process_decision_task
          end
        end

        context "when requesting re-execution per seconds_until_restart" do
          let(:result) { {seconds_until_restart: "321"}.to_json }

          it "schedules a timer event" do
            task.should_receive(:start_timer).with(321, control: result)
            worker.process_decision_task
          end
        end

        context "when not requesting re-execution" do
          let(:result) { {outcome: "some_data"}.to_json }

          it "schedules a workflow completed event" do
            task.should_receive(:complete_workflow_execution).with(result: result)
            worker.process_decision_task
          end
        end
      end

      describe "WorkflowExecutionStarted" do
        let(:event_type) {"WorkflowExecutionStarted"}

        it "should schedule an activity task avoiding defaults" do
          task.should_receive(:schedule_activity_task).with(anything, hash_including(
            heartbeat_timeout: :none,
            input: anything,
            schedule_to_close_timeout: anything,
            schedule_to_start_timeout: anything,
            start_to_close_timeout: anything,
            task_list: "atl",
          ))
          worker.process_decision_task
        end

        it "should use the master activity type" do
          expect(task).to receive(:schedule_activity_task).with { |activity_type|
            expect(activity_type.name).to eq "master-activity"
            expect(activity_type.version).to eq "v1"
          }
          worker.process_decision_task
        end

        context "given no app in charge" do
          let(:input) { ["legacy_stuff", {}].to_json }

          it "should schedule an activity task for a guessed task list" do
            task.should_receive(:schedule_activity_task).with(anything, hash_including(
                task_list: "atl"))
            worker.process_decision_task
          end
        end
      end

      describe "ActivityTaskFailed" do
        let(:event_type) {"ActivityTaskFailed"}

        context "without retry" do
          let(:reason) { "Error" }

          it "should fail" do
            task.should_receive(:fail_workflow_execution)
            worker.process_decision_task
          end

          it "should not re-schedule the task" do
            task.should_not_receive(:schedule_activity_task)
            worker.process_decision_task
          end
        end

        context "with retry" do
          let(:reason) { "Retry" }

          it "should not fail" do
            task.should_not_receive(:fail_workflow_execution)
            worker.process_decision_task
          end

          it "should re-schedule the task" do
            task.should_receive(:schedule_activity_task).with(anything, hash_including(
              heartbeat_timeout: :none,
              input: input,
              schedule_to_close_timeout: anything,
              schedule_to_start_timeout: anything,
              start_to_close_timeout: anything,
              task_list: "atl",
            ))
            worker.process_decision_task
          end
        end
      end

      describe "TimerFired" do
        let(:event_type) {"TimerFired"}
        let(:started_attributes_hash) { {} }
        let(:started_attributes) do
          double("Started Attributes", started_attributes_hash.merge(to_h: started_attributes_hash))
        end
        let(:started_event) { double(attributes: started_attributes, event_id: 4) }
        let(:events) { [event, started_event, event] }
        let(:attributes_hash) do
          {
            child_policy: 1,
            execution_start_to_close_timeout: 2,
            input: input,
            started_event_id: 4,
            tag_list: ["tag"],
            task_list: "list",
            task_start_to_close_timeout: 3,
          }
        end

        context "given an interval option" do
          let(:options) { {interval: 1234} }

          it "should continue with mandatory attributes" do
            task.should_receive(:continue_as_new_workflow_execution).with(hash_including(
                attributes_hash))
            worker.process_decision_task
          end
        end

        context "given seconds_until_restart" do
          let(:control) { {seconds_until_restart: 10}.to_json }
          let(:started_attributes_hash) { {control: control} }

          it "should continue as new" do
            task.should_receive(:continue_as_new_workflow_execution).with(hash_including(
                attributes_hash))
            worker.process_decision_task
          end

          describe "backwards compatibility" do
            let(:control) { {perform_again: 9}.to_json }

            it "should continue as new" do
              task.should_receive(:continue_as_new_workflow_execution)
              worker.process_decision_task
            end
          end
        end

        context "given no interval" do
          it "should re-schedule, assuming seconds_until_retry was set" do
            task.should_receive(:schedule_activity_task).with(anything, hash_including(
              heartbeat_timeout: :none,
              input: input,
              schedule_to_close_timeout: anything,
              schedule_to_start_timeout: anything,
              start_to_close_timeout: anything,
              task_list: "atl",
            ))
            worker.process_decision_task
          end
        end
      end

      context "given an interval" do
        let(:options) { {interval: 1234} }

        events = %w(
          ActivityTaskCompleted
          ActivityTaskFailed
          ActivityTaskTimedOut
        )

        events.each do |event|
          describe event do
            let(:event_type) { event }

            it "should start a timer" do
              task.should_receive(:start_timer).with(1234, anything)
              worker.process_decision_task
            end
          end
        end

        describe "string options for compatibility" do
          let(:event_type) { "ActivityTaskCompleted" }
          let(:input) { ["interval", {}].to_json }

          it "should not be interpreted" do
            task.should_not_receive :start_timer
            worker.process_decision_task
          end
        end
      end
    end
  end

  describe "decision loop" do
    it "should loop processing tasks in subprocesses" do
      worker.should_receive(:in_subprocess).with(:process_decision_task).exactly(9).times
      worker.should_receive(:in_subprocess).with(:process_decision_task).ordered.and_raise "break"
      worker.process_decisions rescue nil
    end
  end
end
