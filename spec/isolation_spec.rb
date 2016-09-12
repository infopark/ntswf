require "ntswf"
require "fileutils"

describe "Isolation" do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.rmtree tmpdir }

  let(:tmpfile) { "#{tmpdir}/test" }
  let(:stored_value) { File.read tmpfile }
  let(:config) do
    {
      decision_task_lists: {
        "primary" => "primary-dtl",
        "another" => "another-dtl",
        "same_as_dtl" => "same-tl",
      },
      activity_task_lists: {
        "primary" => "primary-atl",
        "another" => "another-atl",
        "same_as_dtl" => "same-tl",
      },
      unit: "primary",
      execution_id_prefix: "executionidprefix",
      isolation_file: tmpfile,
    }
  end
  let!(:ntswf) { Ntswf.create(config) }

  subject { stored_value }
  it { is_expected.to match(/\h{18}/) }

  describe "for activity task list" do
    subject { ntswf.activity_task_lists["primary"] }
    it { is_expected.to start_with stored_value }
    it { is_expected.to end_with "primary-atl" }
  end

  describe "for other activity task lists" do
    subject { ntswf.activity_task_lists["another"] }
    it { is_expected.to start_with stored_value }
    it { is_expected.to end_with "another-atl" }
  end

  describe "for decision task list" do
    subject { ntswf.decision_task_list }
    it { is_expected.to end_with "primary-dtl" }
    it { is_expected.to start_with stored_value }
  end

  describe "for other decision task list" do
    subject { ntswf.decision_task_lists["another"] }
    it { is_expected.to end_with "another-dtl" }
    it { is_expected.to start_with stored_value }
  end

  describe "for same task lists" do
    subject { ntswf.activity_task_lists["same_as_dtl"] }
    it { is_expected.to eq ntswf.decision_task_lists["same_as_dtl"] }
  end

  describe "for execution ID prefixes" do
    subject { ntswf.execution_id_prefix }
    it { is_expected.to start_with stored_value }
    it { is_expected.to end_with "executionidprefix" }
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

  describe "backwards compatibility #1" do
    let(:config) { { decision_task_list: {hashy: true}, task_list_suffix_file: tmpfile} }
    subject { ntswf }
    its(:decision_task_list) { should match(/\h{18}/) }
  end

  describe "backwards compatibility #2" do
    let(:config) { { decision_task_list: "legacy-dtl", task_list_suffix_file: tmpfile} }
    subject { ntswf }
    its(:decision_task_list) { should match(/\A\h{18}legacy-dtl\z/) }
  end
end
