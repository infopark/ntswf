require "ntswf"

describe Ntswf::Base do
  let(:config) { { activity_task_lists: {} } }
  let(:base) { Ntswf.create config }
  let(:test_result) { [] }

  describe "processing an activity task" do
    context "given a notification callback" do
      subject do
        base.notify("Exception", {})
        test_result.join
      end

      context "as lambda" do
        before { base.on_notify ->(error) { test_result << "Lambda" } }
        it { should eq "Lambda" }
      end

      context "as block" do
        before { base.on_notify { test_result << "Block" } }
        it { should eq "Block" }
      end

      context "as method" do
        def test_method(options)
          test_result << "Method"
        end

        before { base.on_notify method :test_method }
        it { should eq "Method" }
      end
    end

    describe "the error description" do
      before { base.on_notify ->(error) { test_result << error } }
      subject do
        base.notify("Exception", my_param: :x)
        test_result.first
      end

      its([:message]) { should eq "Exception" }
      its([:params]) { should eq(my_param: :x) }
    end
  end
end
