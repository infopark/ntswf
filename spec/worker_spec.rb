require "ntswf/worker"
require "json"

describe Ntswf::Worker do
  let(:config) { {} }
  let(:worker) { Ntswf.create(:worker, config) }

  before do
    allow(worker).to receive_messages(announce: nil, log: nil)
    worker.instance_exec do
      @rd, @wr = IO.pipe

      def test
        @wr.write({ method: __method__, pid: Process.pid }.to_json)
        @wr.close
      end

      def fail_twice
        fails = @fails.to_i
        @wr.write fails
        @fails = fails + 1
        if fails < 2
          raise "forced exception"
        end
        @wr.write "done"
      end

      def output
        @wr.close
        @rd.read
      end
    end
  end

  describe "subprocess" do
    before { worker.in_subprocess :test }
    subject { JSON.parse worker.output }
    its(["method"]) { should eq "test" }
    its(["pid"]) { should_not be Numeric }
    its(["pid"]) { should_not eq Process.pid }
  end

  describe "retry" do
    before { allow(worker).to receive_messages(exit!: nil, fork: nil) }

    let(:exception) do
      begin
        worker.in_subprocess :fail_twice
        nil
      rescue => e
        e
      end
    end

    let(:output) do
      worker.in_subprocess :fail_twice rescue nil
      worker.output
    end

    context "no retries" do
      subject { output }
      it { is_expected.to eq "0" }

      describe "exception" do
        subject { exception }
        its(:message) { should eq "forced exception" }
      end
    end

    context "single retry" do
      let(:config) { {subprocess_retries: 1} }
      subject { output }
      it { is_expected.to eq "01" }

      describe "exception" do
        subject { exception }
        its(:message) { should eq "forced exception" }
      end
    end

    context "multiple retries" do
      let(:config) { {subprocess_retries: 2} }

      describe "calls" do
        subject { output }
        before { expect(worker).to receive :exit! }
        it { is_expected.to eq "012done" }
      end

      describe "exception" do
        subject { exception }
        it { is_expected.to be_nil }
      end
    end
  end
end
