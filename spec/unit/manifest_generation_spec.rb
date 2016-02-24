require 'rspec/shell/expectations'

RSpec.configure do |c|
  c.include Rspec::Shell::Expectations
end

describe 'spiff manifests' do
  include Rspec::Shell::Expectations
  let(:stubbed_env) { create_stubbed_env }

  context 'on bosh-lite' do
    let(:infrastructure) { 'warden' }

    context 'open source deployment to bosh-lite' do
      it 'should exit 0 on success' do
        stdout, stderr, status = stubbed_env.execute("./scripts/generate-deployment-manifest -e warden")

        expect(status.exitstatus).to eq(0)
      end

      it 'should exit 1 if not enough args given' do
        stdout, stderr, status = stubbed_env.execute("./scripts/generate-deployment-manifest")

        expect(status.exitstatus).to eq(1)
      end

      it 'should give the user a usage message not enough args given' do
        stdout, stderr, status = stubbed_env.execute("./scripts/generate-deployment-manifest")

        expect(stdout).to include("usage:")
      end
    end

    context 'closed source deployment to bosh-lite' do
      it 'should exit 0 on success' do
        stdout, stderr, status = stubbed_env.execute("./scripts/generate-deployment-manifest -c -e warden")

        expect(status.exitstatus).to eq(0)
      end
    end
  end

end
