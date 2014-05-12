require "ntswf"

describe Ntswf::Client do
  let(:client) { Ntswf.create(:client, {}) }
  before { client.stub :log }

  def exception_for
    yield
    nil
  rescue => exception
    exception
  end

  describe "starting an already started execution" do
    before do
      AWS::SimpleWorkflow::WorkflowType.any_instance.stub(:start_execution).and_raise(
          AWS::SimpleWorkflow::Errors::WorkflowExecutionAlreadyStartedFault.new("msg"))
    end

    subject { exception_for { client.start_execution(execution_id: "id") }  }

    it { should be_kind_of Ntswf::Errors::AlreadyStarted }
    its(:message) { should eq "msg" }

    describe "backwards compatibility" do
      it { should be_kind_of AWS::SimpleWorkflow::Errors::WorkflowExecutionAlreadyStartedFault }
    end
  end

  describe "finding an unknown execution" do
    before do
      AWS::SimpleWorkflow::WorkflowExecutionCollection.any_instance.stub(:at).and_raise(
          AWS::SimpleWorkflow::Errors::UnknownResourceFault.new("msg"))
    end

    subject { exception_for { client.find(workflow_id: "id", run_id: "run") }  }

    it { should be_kind_of Ntswf::Errors::NotFound }
    its(:message) { should eq "msg" }

    describe "backwards compatibility" do
      it { should be_kind_of AWS::SimpleWorkflow::Errors::UnknownResourceFault }
    end
  end
end
