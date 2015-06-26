require "ntswf"
require "json"

describe Ntswf::ActivityWorker do
  let(:default_config) { { unit: "test", activity_task_lists: { "test" => "task_list" } } }
  let(:config) { default_config }
  let(:worker) { Ntswf.create(:activity_worker, config) }
  let(:input) { "{}" }
  let(:activity_task) { double activity_type: nil, input: input, workflow_execution: execution }
  let(:execution) { AWS::SimpleWorkflow::WorkflowExecution.new("test", "workflow_id", "run_id") }

  let(:test_result) { [] }

  before { allow(worker).to receive_messages(announce: nil, log: nil) }

  describe "processing an activity task" do
    before do
      allow_any_instance_of(AWS::SimpleWorkflow::ActivityTaskCollection).to receive(:poll_for_single_task).
          and_yield activity_task
    end

    context "given foreign activity type" do
      before { allow(activity_task).to receive_messages activity_type: :some_random_thing }
      specify { expect { worker.process_activity_task }.to_not raise_error }
    end

    context "given a task callback" do
      subject do
        worker.process_activity_task
        test_result.join
      end

      context "as lambda" do
        before { worker.on_activity ->(task) { test_result << "Lambda" } }
        it { is_expected.to eq "Lambda" }
      end

      context "as block" do
        before { worker.on_activity { test_result << "Block" } }
        it { is_expected.to eq "Block" }
      end
    end

    context "having an identify_suffix configured" do
      let(:config) {default_config.merge("identity_suffix" => "id_suff")}

      it "passes the identity to SWF" do
        expect_any_instance_of(AWS::SimpleWorkflow::ActivityTaskCollection).
            to receive(:poll_for_single_task).
            with(anything, identity: "#{Socket.gethostname}:#{Process.pid}:id_suff")

        worker.process_activity_task
      end
    end

    describe "the task description" do
      let(:input) { {name: "name", params: {my_param: :ok}, version: 1}.to_json }
      before { worker.on_activity ->(task) { test_result << task } }
      subject do
        worker.process_activity_task
        test_result.first
      end

      its([:activity_task]) { should eq activity_task }
      its([:name]) { should eq "name" }
      its([:params]) { should eq("my_param" => "ok") }
      its([:run_id]) { should eq "run_id" }
      its([:version]) { should eq 1 }
      its([:workflow_id]) { should eq "workflow_id" }
    end

    describe "the task's return value" do
      let(:callback) { ->(task) { returned } }
      before { worker.on_activity callback }
      context "given an error" do
        let(:message) { "error message" }
        let(:returned) { {error: message} }
        before { expect(activity_task).to receive(:fail!) {|args| test_result << args } }
        before { worker.process_activity_task }

        describe "report to SWF" do
          subject { test_result.first }
          its([:reason]) { should eq "Error" }
          its([:details]) { should eq({error: message}.to_json) }
        end

        describe "keeping SWF limits" do
          let(:message) { "a" * 40000 }
          subject { JSON.parse(test_result.first[:details])["error"] }
          its(:size) { should be <= 32700 }
          its(:size) { should be >= 1000 }
        end
      end

      context "given a retry" do
        let(:returned) { {seconds_until_retry: 45} }
        before { expect(activity_task).to receive(:complete!).with(result: returned.to_json) }
        specify { worker.process_activity_task }
      end

      context "given an error with immediate retry" do
        let(:returned) { {error: "try again", seconds_until_retry: 0} }
        before { expect(activity_task).to receive(:fail!) {|args| test_result << args } }
        before { worker.process_activity_task }

        describe "report to SWF" do
          subject { test_result.first }
          its([:reason]) { should eq "Retry" }
          its([:details]) { should eq({error: "try again"}.to_json) }
        end
      end

      context "given an outcome" do
        let(:outcome) { {is: "ok"} }
        let(:returned) { {outcome: outcome} }
        before { expect(activity_task).to receive(:complete!).with(result: returned.to_json) }
        specify { worker.process_activity_task }
      end

      context "given an exception" do
        let(:message) { "an exception" }
        let(:callback) { ->(task) { raise message } }
        before { expect(activity_task).to receive(:fail!) {|args| test_result << args } }
        before { worker.process_activity_task }

        describe "report to SWF" do
          subject { test_result.first }
          its([:reason]) { should eq "Exception" }
          its([:details]) { should eq({error: "an exception", exception: "RuntimeError"}.to_json) }
        end

        describe "keeping SWF limits" do
          let(:message) { "a" * 40000 }
          subject { JSON.parse(test_result.first[:details])["error"] }
          its(:size) { should be <= 32700 }
          its(:size) { should be >= 1000 }
        end
      end
    end
  end

  describe "activity loop" do
    it "should loop processing tasks in subprocesses" do
      expect(worker).to receive(:in_subprocess).with(:process_activity_task).exactly(9).times
      expect(worker).to receive(:in_subprocess).with(:process_activity_task).ordered.and_raise "break"
      worker.process_activities rescue nil
    end
  end
end
