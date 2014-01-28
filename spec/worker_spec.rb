require "ntswf/worker"
require "json"

describe Ntswf::Worker do
  class Worker
    include Ntswf::Worker

    def initialize(config)
      super config
      @rd, @wr = IO.pipe
    end

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

  before { Worker.any_instance.stub(announce: nil, log: nil) }

  let(:worker) { Worker.new({}) }

  describe "subprocess" do
    before { worker.in_subprocess :test }
    subject { JSON.parse worker.output }
    its(["method"]) { should eq "test" }
    its(["pid"]) { should_not be Numeric }
    its(["pid"]) { should_not eq Process.pid }
  end

  describe "retry" do
    before { worker.stub(exit!: nil, fork: nil) }

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
      it { should eq "0" }

      describe "exception" do
        subject { exception }
        its(:message) { should eq "forced exception" }
      end
    end

    context "single retry" do
      let(:worker) { Worker.new(subprocess_retries: 1) }
      subject { output }
      it { should eq "01" }

      describe "exception" do
        subject { exception }
        its(:message) { should eq "forced exception" }
      end
    end

    context "multiple retries" do
      let(:worker) { Worker.new(subprocess_retries: 2) }

      describe "calls" do
        subject { output }
        before { worker.should_receive :exit! }
        it { should eq "012done" }
      end

      describe "exception" do
        subject { exception }
        it { should be_nil }
      end
    end
  end
end
