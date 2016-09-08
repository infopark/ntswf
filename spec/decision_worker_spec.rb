require "ntswf"
require "json"

describe Ntswf::DecisionWorker do
  let(:default_config) do
    {
      unit: "default-unit",
      decision_task_list: "default-dtl",
      activity_task_lists: {
        "default-unit" => "default-unit-atl",
        "other-unit" => "other-unit-atl",
        "test" => "unit_by_workflow_type-atl",
      }
    }
  end

  let(:config) { default_config }
  let(:worker) { Ntswf.create(:decision_worker, config) }

  let(:options) { {} }
  let(:input) { options.merge('params' => {'key' => 'value'}).to_json }
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

  before { allow(worker).to receive_messages(announce: nil, log: nil) }

  describe "processing a decision task" do
    subject(:process_task) { worker.process_decision_task }

    context "polling for an event" do
      it "should only query for the configured task list" do
        expect_any_instance_of(AWS::SimpleWorkflow::DecisionTaskCollection).
            to receive(:poll_for_single_task).with("default-dtl", {})
        process_task
      end

      context "having an identify_suffix configured" do
        let(:config) {default_config.merge("identity_suffix" => "id_suff")}

        it "passes the identity to SWF" do
          expect_any_instance_of(AWS::SimpleWorkflow::DecisionTaskCollection).
              to receive(:poll_for_single_task).
              with(anything, identity: "#{Socket.gethostname}:#{Process.pid}:id_suff")

          process_task
        end
      end
    end

    context "handling event" do
      before do
        allow_any_instance_of(AWS::SimpleWorkflow::DecisionTaskCollection).to receive(
            :poll_for_single_task).and_yield(task)
      end

      shared_examples_for "scheduling an activity task" do
        it "schedules an activity task" do
          expect(task).to receive(:schedule_activity_task).with(anything, hash_including(
            heartbeat_timeout: :none,
            input: input,
            schedule_to_close_timeout: anything,
            schedule_to_start_timeout: anything,
            start_to_close_timeout: anything,
          ))
          process_task
        end

        it "uses the master activity type" do
          expect(task).to receive(:schedule_activity_task) {|activity_type|
            expect(activity_type.name).to eq "master-activity"
            expect(activity_type.version).to eq "v1"
          }
          process_task
        end

        shared_examples_for "handling task specific activity group" do |expected_task_list|
          context "without activity group specified" do
            context "without activity group configured" do
              let(:config) { default_config.reject {|k, _| k == :activity_group } }

              it "schedules an activity task for the unit's task list" do
                expect(task).to receive(:schedule_activity_task).with(anything, hash_including(
                    task_list: expected_task_list))
                process_task
              end
            end

            context "with activity group configured" do
              let(:config) { default_config.merge(activity_group: "default_group") }

              it "schedules an activity task for the default group's task list" do
                expect(task).to receive(:schedule_activity_task).with(anything, hash_including(
                    task_list: "#{expected_task_list}-default_group"))
                process_task
              end
            end
          end

          context "with activity group specified" do
            let(:options) { super().merge(activity_group: "special-task-force") }

            context "without activity group configured" do
              let(:config) { default_config.reject {|k, _| k == :activity_group } }

              it "schedules an activity task for the given group's task list" do
                expect(task).to receive(:schedule_activity_task).with(anything, hash_including(
                    task_list: "#{expected_task_list}-special-task-force"))
                process_task
              end
            end

            context "with activity group configured" do
              let(:config) { default_config.merge(activity_group: "default_group") }

              it "schedules an activity task for the given group's task list" do
                expect(task).to receive(:schedule_activity_task).with(anything, hash_including(
                    task_list: "#{expected_task_list}-special-task-force"))
                process_task
              end
            end
          end
        end

        context "with unit given" do
          let(:options) { {unit: "other-unit"} }

          it_behaves_like "handling task specific activity group", "other-unit-atl"
        end

        context "with unit not given" do
          let(:options) { {} }

          it "uses a guessed task list" do
            expect(task).to receive(:schedule_activity_task).with(anything, hash_including(
                task_list: "unit_by_workflow_type-atl"))
            process_task
          end

          it_behaves_like "handling task specific activity group", "unit_by_workflow_type-atl"
        end

        context "for legacy input" do
          let(:input) { ["legacy_stuff", {}].to_json }

          context "without activity group configured" do
            let(:config) { default_config.reject {|k, _| k == :activity_group } }

            it "uses a guessed task list" do
              expect(task).to receive(:schedule_activity_task).with(anything, hash_including(
                  task_list: "unit_by_workflow_type-atl"))
              process_task
            end
          end

          context "with activity group configured" do
            let(:config) { default_config.merge(activity_group: "default_group") }

            it "schedules an activity task for the default group's task list" do
              expect(task).to receive(:schedule_activity_task).with(anything, hash_including(
                  task_list: "unit_by_workflow_type-atl-default_group"))
              process_task
            end
          end
        end
      end

      context "ActivityTaskTimedOut" do
        let(:event_type) {"ActivityTaskTimedOut"}

        it "should cancel the execution" do
          expect(task).to receive :cancel_workflow_execution
          process_task
        end

        it "should notify" do
          expect(worker).to receive :notify
          process_task
        end
      end

      context "ActivityTaskCompleted" do
        let(:event_type) {"ActivityTaskCompleted"}

        context "when requesting re-execution per seconds_until_retry" do
          let(:result) { {seconds_until_retry: 321}.to_json }

          it "schedules a timer event" do
            expect(task).to receive(:start_timer).with(321, anything)
            process_task
          end
        end

        context "when requesting re-execution per seconds_until_restart" do
          let(:result) { {seconds_until_restart: "321"}.to_json }

          it "schedules a timer event" do
            expect(task).to receive(:start_timer).with(321, control: result)
            process_task
          end
        end

        context "when not requesting re-execution" do
          let(:result) { {outcome: "some_data"}.to_json }

          it "schedules a workflow completed event" do
            expect(task).to receive(:complete_workflow_execution).with(result: result)
            process_task
          end
        end
      end

      context "WorkflowExecutionStarted" do
        let(:event_type) {"WorkflowExecutionStarted"}

        it_behaves_like "scheduling an activity task"
      end

      context "ActivityTaskFailed" do
        let(:event_type) {"ActivityTaskFailed"}

        context "without retry" do
          let(:reason) { "Error" }

          it "should fail" do
            expect(task).to receive(:fail_workflow_execution)
            process_task
          end

          it "should not re-schedule the task" do
            expect(task).not_to receive(:schedule_activity_task)
            process_task
          end
        end

        context "with retry" do
          let(:reason) { "Retry" }

          it "does not fail" do
            expect(task).not_to receive(:fail_workflow_execution)
            process_task
          end

          it_behaves_like "scheduling an activity task"
        end
      end

      context "TimerFired" do
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
            expect(task).to receive(:continue_as_new_workflow_execution).with(hash_including(
                attributes_hash))
            process_task
          end
        end

        context "given seconds_until_restart" do
          let(:control) { {seconds_until_restart: 10}.to_json }
          let(:started_attributes_hash) { {control: control} }

          it "should continue as new" do
            expect(task).to receive(:continue_as_new_workflow_execution).with(hash_including(
                attributes_hash))
            process_task
          end

          context "backwards compatibility" do
            let(:control) { {perform_again: 9}.to_json }

            it "should continue as new" do
              expect(task).to receive(:continue_as_new_workflow_execution)
              process_task
            end
          end
        end

        context "given no interval" do
          let(:options) { {} }

          it_behaves_like "scheduling an activity task"
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
              expect(task).to receive(:start_timer).with(1234, anything)
              process_task
            end
          end
        end

        context "string options for compatibility" do
          let(:event_type) { "ActivityTaskCompleted" }
          let(:input) { ["interval", {}].to_json }

          it "should not be interpreted" do
            expect(task).not_to receive :start_timer
            process_task
          end
        end
      end
    end
  end

  describe "decision loop" do
    it "should loop processing tasks in subprocesses" do
      expect(worker).to receive(:in_subprocess).with(:process_decision_task).exactly(9).times
      expect(worker).to receive(:in_subprocess).with(:process_decision_task).ordered.and_raise "break"
      worker.process_decisions rescue nil
    end
  end
end
