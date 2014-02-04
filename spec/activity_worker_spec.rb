require "ntswf"

describe Ntswf::ActivityWorker do
  let(:config) { { unit: "test", activity_task_lists: { "test" => "task_list" } } }
  let(:worker) { Ntswf.create(:activity_worker, config) }
  let(:activity_task) { double input: "{}" }

  before { worker.stub(announce: nil, log: nil) }

  describe "processing an activity task" do
    before do
      AWS::SimpleWorkflow::ActivityTaskCollection.any_instance.stub(:poll_for_single_task).
          and_yield activity_task
    end

    context "given foreign activity type" do
      before { activity_task.stub activity_type: :some_random_thing }
      subject { worker.process_activity_task { :accepted } }
      it { should eq :accepted }
    end
  end

  describe "activity loop" do
    it "should loop processing tasks in subprocesses" do
      worker.should_receive(:in_subprocess).with(:process_activity_task).exactly(9).times
      worker.should_receive(:in_subprocess).with(:process_activity_task).ordered.and_raise "break"
      worker.process_activities rescue nil
    end
  end
end
