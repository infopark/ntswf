require "ntswf"

describe Ntswf::Client do
  let(:client) { Ntswf.create(:activity_worker, :client, {activity_task_lists: {}}) }
  before { allow(client).to receive :log }

  def exception_for
    yield
    nil
  rescue => exception
    exception
  end

  describe "starting an already started execution" do
    before do
      allow_any_instance_of(AWS::SimpleWorkflow::WorkflowType).to receive(:start_execution).and_raise(
          AWS::SimpleWorkflow::Errors::WorkflowExecutionAlreadyStartedFault.new("msg"))
    end

    subject { exception_for { client.start_execution(execution_id: "id") }  }

    it { is_expected.to be_kind_of Ntswf::Errors::AlreadyStarted }
    its(:message) { should eq "msg" }

    describe "backwards compatibility" do
      it { is_expected.to be_kind_of AWS::SimpleWorkflow::Errors::WorkflowExecutionAlreadyStartedFault }
    end
  end

  describe "finding an unknown execution" do
    before do
      allow_any_instance_of(AWS::SimpleWorkflow::WorkflowExecutionCollection).to receive(:at).and_raise(
          AWS::SimpleWorkflow::Errors::UnknownResourceFault.new("msg"))
    end

    subject { exception_for { client.find(workflow_id: "id", run_id: "run") }  }

    it { is_expected.to be_kind_of Ntswf::Errors::NotFound }
    its(:message) { should eq "msg" }

    describe "backwards compatibility" do
      it { is_expected.to be_kind_of AWS::SimpleWorkflow::Errors::UnknownResourceFault }
    end
  end

  describe "invalid arguments" do
    describe "given invalid task list name" do
      subject { exception_for { client.configure(activity_task_lists: { a: "not valid" }) } }
      it { is_expected.to be_kind_of RuntimeError }
      it { is_expected.to be_kind_of Ntswf::Errors::InvalidArgument }
      its(:message) { should include "Invalid config" }
    end

    describe "given task list name with reserved separator" do
      subject { exception_for { client.configure(activity_task_lists: { a: "a;b" }) } }
      it { is_expected.to be_kind_of Ntswf::Errors::InvalidArgument }
      its(:message) { should include "reserved" }
    end

    describe "given no activity task list mapping" do
      subject { exception_for { client.process_activity_task } }
      it { is_expected.to be_kind_of Ntswf::Errors::InvalidArgument }
      its(:message) { should include "Missing activity task list" }
    end
  end
end
