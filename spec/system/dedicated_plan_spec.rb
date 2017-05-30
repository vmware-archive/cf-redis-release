require 'system_spec_helper'
require 'system/shared_examples/redis_instance'

require 'prof/external_spec/shared_examples/service'
require 'prof/marketplace_service'
require 'prof/service_instance'

LUA_INFINITE_LOOP = 'while true do end'

describe 'dedicated plan' do
  def service
    Prof::MarketplaceService.new(
      name: bosh_manifest.property('redis.broker.service_name'),
      plan: 'dedicated-vm'
    )
  end

  before(:all) do
    @service_broker_host = bosh_director.ips_for_job(environment.bosh_service_broker_job_name, bosh_manifest.deployment_name).first
  end

  let(:redis_config_command) { bosh_manifest.property('redis.config_command') }

  # defining manually_drain skips duplicate shared_example within prof
  let(:manually_drain) { '' }
  it_behaves_like 'a persistent cloud foundry service'

  it 'preserves data when recreating vms' do
    service_broker.provision_and_bind(service.name, service.plan) do |service_binding|
      service_client = service_client_builder(service_binding)
      service_client.write('test_key', 'test_value')
      expect(service_client.read('test_key')).to eq('test_value')

      bosh_director.stop(environment.bosh_service_broker_job_name, 0)
      host = bosh_director.ips_for_job(environment.bosh_service_broker_job_name, bosh_manifest.deployment_name).first

      bosh_director.recreate_all([environment.bosh_service_broker_job_name])

      expect(service_client.read('test_key')).to eq('test_value')
    end
  end

  let(:admin_command_availability) do
    {
      'DEBUG' => false,
      'SHUTDOWN' => false,
      'SLAVEOF' => false,
      'SYNC' => false,
      'CONFIG' => false,

      'SAVE' => true,
      'BGSAVE' => true,
      'BGREWRITEAOF' => true,
      'MONITOR' => true
    }
  end

  it_behaves_like 'a redis instance'

  describe 'redis provisioning' do
    before(:all) do
      @preprovision_timestamp = ssh_gateway.execute_on(@service_broker_host, "date +%s")
      @service_instance       = service_broker.provision_instance(service.name, service.plan)
      @binding                = service_broker.bind_instance(@service_instance)
    end

    after(:all) do
      service_broker.unbind_instance(@binding)
      service_broker.deprovision_instance(@service_instance)
    end

    describe 'configuration' do
      it 'has the correct maxmemory' do
        client = service_client_builder(@binding)
        expect(client.config['maxmemory'].to_i).to be > 0
      end

      it 'has the correct maxclients' do
        client = service_client_builder(@binding)
        expect(client.config['maxclients']).to eq("10000")
      end

      it 'runs correct version of redis' do
        client = service_client_builder(@binding)
        expect(client.info('redis_version')).to eq('3.2.8')
      end

      it 'requires a password' do
        wrong_credentials = @binding.credentials.reject { |k, v| !([:host, :port].include?(k)) }
        allow(@binding).to receive(:credentials).and_return(wrong_credentials)

        client = service_client_builder(@binding)
        expect { client.write('foo', 'bar') }.to raise_error(/NOAUTH Authentication required/)
      end
    end

    it 'logs instance provisioning' do
      vm_log = root_execute_on(@service_broker_host, 'cat /var/log/syslog')
      contains_expected_log = drop_log_lines_before(@preprovision_timestamp, vm_log).any? do |line|
        line.include?('Successfully provisioned Redis instance') &&
        line.include?('dedicated-vm') &&
        line.include?(@service_instance.id)
      end

      expect(contains_expected_log).to be true
    end
  end

  describe 'redis deprovisioning' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @predeprovision_timestamp = ssh_gateway.execute_on(@service_broker_host, 'date +%s')
      service_broker.deprovision_instance(@service_instance)
    end

    it 'logs instance deprovisioning' do
      vm_log = root_execute_on(@service_broker_host, 'cat /var/log/syslog')
      contains_expected_log = drop_log_lines_before(@predeprovision_timestamp, vm_log).any? do |line|
        line.include?('Successfully deprovisioned Redis instance') &&
        line.include?('dedicated-vm') &&
        line.include?(@service_instance.id)
      end

      expect(contains_expected_log).to be true
    end
  end

  it 'retains data and keeps the same credentials after recreating the node' do
    service_broker.provision_and_bind(service.name, service.plan) do |service_binding|
      service_instance_host = service_binding.credentials.fetch(:host)
      client                = service_client_builder(service_binding)

      # Write to dedicated node
      client.write('test_key', 'test_value')
      expect(client.read('test_key')).to eql('test_value')

      # Restart dedicated node
      dedicated_node_index = bosh_director.ips_for_job(Helpers::Environment::DEDICATED_NODE_JOB_NAME, bosh_manifest.deployment_name).index(service_instance_host)
      expect(dedicated_node_index).to_not be_nil
      bosh_director.recreate_instance(Helpers::Environment::DEDICATED_NODE_JOB_NAME, dedicated_node_index)

      # Ensure data is intact
      expect(client.read('test_key')).to eq('test_value')
    end
  end

  describe 'recycled instances' do
    before(:all) do
      @service_instances = allocate_all_instances!
      service_instance = @service_instances.pop

      service_broker.bind_instance(service_instance) do |service_binding|
        @old_credentials        = service_binding.credentials
        @old_client             = service_client_builder(service_binding)

        @old_client.write('test_key', 'test_value')
        expect(@old_client.read('test_key')).to eq('test_value')
        expect(@old_client.aof_contents).to include('test_value')

        @script_sha = @old_client.script_load('return 1')
        expect(@old_client.script_exists(@script_sha)).to be true

        @original_config_maxmem = @old_client.config.fetch('maxmemory-policy')
        @old_client.write_config('maxmemory-policy', 'allkeys-lru')
        expect(@old_client.config.fetch('maxmemory-policy')).to eql('allkeys-lru')
        expect(@old_client.config.fetch('maxmemory-policy')).to_not eql(@original_config_maxmem)
      end

      service_broker.deprovision_instance(service_instance)

      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @service_binding  = service_broker.bind_instance(@service_instance)
    end

    after(:all) do
      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)

      @service_instances.each do |service_instance|
        service_broker.deprovision_instance(service_instance)
      end
    end

    it 'cleans the aof file' do
      new_client = service_client_builder(@service_binding)
      expect(new_client.aof_contents).to_not include('test_value')
    end

    it 'cleans the data' do
      new_client = service_client_builder(@service_binding)
      expect(new_client.read('test_key')).to_not eq('test_value')
    end

    it 'resets the configuration' do
      new_client = service_client_builder(@service_binding)
      expect(new_client.config.fetch('maxmemory-policy')).to eq(@original_config_maxmem)
      expect(new_client.config.fetch('maxmemory-policy')).to_not eq('allkeys-lru')
    end

    it 'invalidates the old credentials' do
      expect { @old_client.read('foo') }.to raise_error(/invalid password/)
    end

    it 'changes the credentials' do
      original_password = @old_credentials.fetch(:password)
      new_password = @service_binding.credentials.fetch(:password)

      expect(new_password).to_not eq(original_password)
    end

    it 'flushes the script cache' do
      new_client = service_client_builder(@service_binding)
      expect(new_client.script_exists(@script_sha)).to be false
    end
  end

  describe 'scripts running' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @service_binding  = service_broker.bind_instance(@service_instance)

      new_client = service_client_builder(@service_binding)
      @infinite_loop_sha = new_client.script_load(LUA_INFINITE_LOOP)
      expect(new_client.script_exists(@infinite_loop_sha)).to be true

      Thread.new { @new_client.evalsha @infinite_loop_sha, 0 }
    end

    it 'successfully deprovisions' do
      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)
    end
  end
end

def allocate_all_instances!
  max_instances = bosh_manifest.property('redis.broker.dedicated_nodes').length
  max_instances.times.map { service_broker.provision_instance(service.name, service.plan) }
end
