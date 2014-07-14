require "ntswf"
require "fileutils"

describe "Isolation" do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rmtree tmpdir }

  let(:tmpfile) { "#{tmpdir}/test" }
  let(:stored_value) { File.read tmpfile }
  let(:config) do
    {
      activity_task_lists: {
        "primary" => "primary-atl",
        "another" => "another-atl",
        "same_as_dtl" => "test",
      },
      decision_task_list: "test",
      execution_id_prefix: "executionidprefix",
      isolation_file: tmpfile,
    }
  end
  let!(:ntswf) { Ntswf.create(config) }

  subject { stored_value }
  it { should match(/\h{18}/) }

  describe "for activity task list" do
    subject { ntswf.activity_task_lists["primary"] }
    it { should start_with stored_value }
    it { should end_with "primary-atl" }
  end

  describe "for other activity task lists" do
    subject { ntswf.activity_task_lists["another"] }
    it { should start_with stored_value }
    it { should end_with "another-atl" }
  end

  describe "for decision task list" do
    subject { ntswf.decision_task_list }
    it { should end_with "test" }
    it { should start_with stored_value }
  end

  describe "for same task lists" do
    subject { ntswf.activity_task_lists["same_as_dtl"] }
    it { should eq ntswf.decision_task_list }
  end

  describe "for execution ID prefixes" do
    subject { ntswf.execution_id_prefix }
    it { should start_with stored_value }
    it { should end_with "executionidprefix" }
  end

  describe "ignored if not configured" do
    subject { Ntswf.create({decision_task_list: "x"}) }
    its(:decision_task_list) { should_not include stored_value }
    its(:execution_id_prefix) { should_not include stored_value }
  end

  describe "if existing" do
    let(:new_instance) { Ntswf.create(config) }
    subject { new_instance }
    its(:activity_task_lists) { should eq ntswf.activity_task_lists }
    its(:decision_task_list) { should eq ntswf.decision_task_list }
    its(:execution_id_prefix) { should eq ntswf.execution_id_prefix }
  end

  describe "backwards compatibility" do
    let(:config) { { decision_task_list: {hashy: true}, task_list_suffix_file: tmpfile} }
    subject { ntswf }
    its(:decision_task_list) { should match(/\h{18}/) }
  end
end
