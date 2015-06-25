require "ntswf/utils"

describe Ntswf::Utils do
  let(:utils) { Ntswf.create(:utils) }

  describe "registering the workflow type" do
    it "should configure minimal defaults" do
      expect_any_instance_of(AWS::SimpleWorkflow::WorkflowTypeCollection).to receive(:register).with(
          "master-workflow", "v1")
      utils.register_workflow_type
    end
  end

  describe "registering the activity type" do
    it "should configure minimal defaults" do
      expect_any_instance_of(AWS::SimpleWorkflow::ActivityTypeCollection).to receive(:register).with(
          "master-activity", "v1")
      utils.register_activity_type
    end
  end
end
