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

    it 'should generate manifest' do
      example_manifest = Tempfile.new("example-manifest.yml")

      @clazz.process("scripts/generate_deployment_manifest #{infrastructure} #{stub} > #{example_manifest.path}", expected_exit_status: 0)

      expected = File.read("spec/fixtures/cf-redis-#{infrastructure}.yml")
      actual = File.read(example_manifest.path)
      expect(actual).to yaml_eq(expected)
    end

    it 'should allow users to override the jobs section' do
      custom_jobs_file = Tempfile.new("custom-jobs.yml")
      custom_jobs_file.write({
            'additional_releases' => [
              {'name' => 'another-redis-release', 'version' => 'latest'},
              {'name' => 'my-custom-release', 'version' => 'latest'}]}.to_yaml)
      custom_jobs_file.close
      example_manifest = Tempfile.new("example-manifest.yml")

      @clazz.process("scripts/generate_deployment_manifest #{infrastructure} #{stub} #{custom_jobs_file.path} > #{example_manifest.path}", expected_exit_status: 0)

      actual = YAML.load(File.read(example_manifest.path))
      expect(actual['releases']).to include({ 'name' => 'cf-redis', 'version' => 'latest'})
      expect(actual['releases']).to include({ 'name' => 'another-redis-release', 'version' => 'latest'})
      expect(actual['releases']).to include({ 'name' => 'my-custom-release', 'version' => 'latest'})
    end
  end
end
