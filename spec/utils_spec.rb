require "ntswf/utils"

describe Ntswf::Utils do
  let(:utils) { Ntswf.create(:utils) }

  describe "registering the workflow type" do
    it "should configure minimal defaults" do
      AWS::SimpleWorkflow::WorkflowTypeCollection.any_instance.should_receive(:register).with(
          "master-workflow", "v1")
      utils.register_workflow_type
    end
  end

  describe "registering the activity type" do
    it "should configure minimal defaults" do
      AWS::SimpleWorkflow::ActivityTypeCollection.any_instance.should_receive(:register).with(
          "master-activity", "v1")
      utils.register_activity_type
    end
  end
end
