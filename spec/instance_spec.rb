require "ntswf"

describe Ntswf::Instance do
  describe 'creating an instance' do
    subject { Ntswf::Instance.new(*args) }
    let(:args) { [] }
    it { is_expected.to be_an Ntswf::Instance }

    context 'given a module' do
      let(:args) { [:client] }
      it { is_expected.to be_an Ntswf::Client }
      it { is_expected.not_to be_an Ntswf::ActivityWorker }
    end

    context 'given multiple modules' do
      let(:args) { [:activity_worker, :decision_worker] }
      it { is_expected.not_to be_an Ntswf::Client }
      it { is_expected.to be_an Ntswf::ActivityWorker }
      it { is_expected.to be_an Ntswf::DecisionWorker }
    end

    context 'given no module' do
      let(:args) { [] }
      it { is_expected.to be_an Ntswf::Client }
      it { is_expected.to be_an Ntswf::ActivityWorker }
      it { is_expected.to be_an Ntswf::DecisionWorker }
    end

    describe 'passing configuration' do
      subject { Ntswf.create(:client, domain: "test").domain }
      its(:name) { should eq "test" }
    end
  end
end
