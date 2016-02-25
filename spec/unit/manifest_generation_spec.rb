require 'support/yaml_eq'
require 'yaml'
require 'pry'
require 'rspec/shell/expectations'


describe 'manifest generator' do
  include Rspec::Shell::Expectations
  let(:stubbed_env) { create_stubbed_env }

  context 'with no arguments' do
    it 'should exit with a non-zero status' do
      stdout, stderr, status = stubbed_env.execute("scripts/generate-deployment-manifest")

      expect(stderr).to include("usage:")
      expect(status.exitstatus).to eq(1)
    end
  end

  context 'with a bosh-lite' do
    let(:stub) { 'templates/sample_stubs/meta.yml' }
    let(:infrastructure) { 'templates/sample_stubs/infrastructure-warden.yml templates/sample_stubs/meta.yml' }
    let(:example_manifest) { Tempfile.new("example-manifest.yml") }
    let(:custom_jobs_file) { Tempfile.new("custom-jobs.yml") }
    let(:actual_yaml) { YAML.load(File.read(example_manifest.path)) }

    it 'should generate manifest' do
      stdout, stderr, status = stubbed_env.execute("scripts/generate-deployment-manifest #{infrastructure}")

      expected = File.read("spec/fixtures/cf-redis.yml")
      expect(stdout).to yaml_eq(expected)
    end

    it 'should merge additional properties from a stub' do
      sample_properties = { 'sample' => 'property' }
      custom_jobs_file.write({
        'properties' => sample_properties
      }.to_yaml)
      custom_jobs_file.close

      stdout, stderr, status = stubbed_env.execute("scripts/generate-deployment-manifest #{infrastructure} #{custom_jobs_file.path} > #{example_manifest.path}")

      expect(actual_yaml['properties']).to include(sample_properties)
    end

    it 'should merge additional releases from a stub' do
      additional_releases = []
      additional_releases << {'name' => 'another-redis-release', 'version' => 'latest'}
      additional_releases << {'name' => 'my-custom-release', 'version' => 'latest'}
      custom_jobs_file.write({
        'additional_releases' => additional_releases
      }.to_yaml)
      custom_jobs_file.close

      stdout, stderr, status = stubbed_env.execute("scripts/generate-deployment-manifest #{infrastructure} #{custom_jobs_file.path} > #{example_manifest.path}")

      expect(actual_yaml['releases'].size).to be > additional_releases.size
      expect(actual_yaml['releases']).to include(additional_releases[0])
      expect(actual_yaml['releases']).to include(additional_releases[1])
    end

    it 'should merge additional job properties from a stub' do
      custom_jobs_file.write({
        'jobs' => [
            {
              'name' => 'cf-redis-broker',
              'properties' => {
                'closed' => 'source'
              }
            }
        ]
      }.to_yaml)
      custom_jobs_file.close

      stdout, stderr, status = stubbed_env.execute("scripts/generate-deployment-manifest #{infrastructure} #{custom_jobs_file.path} > #{example_manifest.path}")

      redis_broker_job = actual_yaml['jobs'].select{|i| i['name'] == 'cf-redis-broker' }.first
      expect(redis_broker_job['properties']).to include({'closed'=>'source'})
    end

    it 'should merge additional job templates from a stub' do
      job_template = { 'name' => 'backup-example', 'release' => 'colocated-release' }
      custom_jobs_file.write({
        'additional_job_templates' => {
          'cf_redis_broker' => [job_template]
        },
      }.to_yaml)
      custom_jobs_file.close

      stdout, stderr, status = stubbed_env.execute("scripts/generate-deployment-manifest #{infrastructure} #{custom_jobs_file.path} > #{example_manifest.path}")

      redis_broker_job = actual_yaml['jobs'].select{|i| i['name'] == 'cf-redis-broker' }.first
      expect(redis_broker_job['templates']).to include(job_template)
    end
  end
end
