require "ntswf"

describe Ntswf::ActivityWorker do
  class Worker
    include Ntswf::ActivityWorker
  end

  before { Worker.any_instance.stub(announce: nil, log: nil) }

  let(:config) { { unit: "test", activity_task_lists: { "test" => "task_list" } } }
  let(:worker) { Worker.new config }
  let(:activity_task) { mock input: "{}" }

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
end
