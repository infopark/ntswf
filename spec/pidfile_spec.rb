require "ntswf/worker"
require "tempfile"

describe "PID file" do
  let(:tmpfile) { Tempfile.new "test" }
  let(:config) { {pidfile: tmpfile.path} }
  let(:worker) { Ntswf.create(:worker, config) }

  before { allow(worker).to receive_messages(announce: nil, log: nil) }

  def run_subprocess
    worker.in_subprocess :hash
  end

  before { run_subprocess }

  describe "storing the current PID" do
    subject { File.read tmpfile.path }
    it { is_expected.to eq Process.pid.to_s }
  end

  describe "validating the PID" do
    context "when modified" do
      before { File.write(tmpfile.path, "something else") }
      before { expect(worker).to receive(:notify).with(/changed.+PID file/, anything) }
      specify { expect { run_subprocess }.to raise_error SystemExit }
    end

    context "when not modified" do
      specify { expect { run_subprocess }.not_to raise_error }
    end
  end
end
