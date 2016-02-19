require 'support/yaml_eq'
require 'yaml'
require 'process_helper'

# Dummy fixture class
class Clazz
  include ProcessHelper
end

describe 'spiff manifests' do
  before :each do
    @clazz = Clazz.new
  end

  context 'open source bosh-lite' do
    let(:stub) { 'templates/sample_stubs/sample_warden_stub.yml' }
    let(:infrastructure) { 'warden' }

    it 'should do stuff' do
      example_manifest = Tempfile.new("example-manifest.yml")

      @clazz.process("scripts/generate_deployment_manifest #{infrastructure} #{stub} > #{example_manifest.path}", expected_exit_status: 0)

      expected = File.read("spec/fixtures/cf-redis-#{infrastructure}.yml")
      actual = File.read(example_manifest.path)
      expect(actual).to yaml_eq(expected)
    end
  end
end
