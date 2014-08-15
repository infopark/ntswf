require "ntswf"

describe Ntswf::Instance do
  describe 'creating an instance' do
    subject { Ntswf::Instance.new(*args) }
    let(:args) { [] }
    it { should be_an Ntswf::Instance }

    context 'given a module' do
      let(:args) { [:client] }
      it { should be_an Ntswf::Client }
      it { should_not be_an Ntswf::ActivityWorker }
    end

    context 'given multiple modules' do
      let(:args) { [:activity_worker, :decision_worker] }
      it { should_not be_an Ntswf::Client }
      it { should be_an Ntswf::ActivityWorker }
      it { should be_an Ntswf::DecisionWorker }
    end

    context 'given no module' do
      let(:args) { [] }
      it { should be_an Ntswf::Client }
      it { should be_an Ntswf::ActivityWorker }
      it { should be_an Ntswf::DecisionWorker }
    end

    describe 'passing configuration' do
      subject { Ntswf.create(:client, domain: "test").domain }
      its(:name) { should eq "test" }
    end
  end
end

describe Ntswf::Instance, "full featured" do
  subject {Ntswf::Instance.new}

  def own_instance_methods(mod)
    method_retrievers = [:instance_methods, :private_instance_methods]
    methods = []
    method_retrievers.each do |method_retriever|
      methods.concat(mod.send(method_retriever))
    end
    mod.ancestors.each do |a|
      a == mod and next
      method_retrievers.each do |method_retriever|
        methods -= a.send(method_retriever)
      end
    end
    methods
  end

  it "is not composed of colliding methods" do
    # out of scope: non-instance methods considered
    # out of scope: methods calling super may not be colliding methods
    ntswf_modules = (class << subject; included_modules; end).select {|a| a.name[0, 7] == "Ntswf::"}
    ntswf_modules.each do |left|
      ntswf_modules.each do |right|
        left == right and next
        unless (left < right || right < left)
          expect(own_instance_methods(left) & own_instance_methods(right)).to eq([])
        end
      end
    end
  end
end

