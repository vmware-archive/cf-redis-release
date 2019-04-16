require 'system_spec_helper'
require 'system/shared_examples/redis_instance'
require 'system/shared_examples/service'

LUA_INFINITE_LOOP = 'while true do end'

describe 'dedicated plan' do
  def service_name
    test_manifest['properties']['redis']['broker']['service_name']
  end

  def service_plan_name
    'dedicated-vm'
  end

  def bosh
    Helpers::Bosh2.new
  end

  let(:redis_config_command) { test_manifest['properties']['redis']['config_command'] }

  it_behaves_like 'a persistent cloud foundry service'

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
      @preprovision_timestamp = bosh.ssh(deployment_name, Helpers::Environment::BROKER_JOB_NAME, 'date +%s')
      @service_instance = service_broker.provision_instance(service_name, service_plan_name)
      @binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
    end

    after(:all) do
      service_plan = service_broker.service_plan(service_name, service_plan_name)

      service_broker.unbind_instance(@binding, service_plan)
      service_broker.deprovision_instance(@service_instance, service_plan)
    end

    describe 'configuration' do
      it 'has the correct maxmemory' do
        client = service_client_builder(@binding)
        expect(client.config['maxmemory'].to_i).to be > 0
      end

      it 'has the correct maxclients' do
        client = service_client_builder(@binding)
        expect(client.config['maxclients']).to eq('10000')
      end

      it 'runs correct version of redis' do
        client = service_client_builder(@binding)
        expect(client.info('redis_version')).to eq('5.0.4')
      end

      it 'requires a password' do
        wrong_credentials = @binding.credentials.reject { |k, v| !([:host, :port].include?(k)) }
        allow(@binding).to receive(:credentials).and_return(wrong_credentials)

        client = service_client_builder(@binding)
        expect { client.write('foo', 'bar') }.to raise_error(/NOAUTH Authentication required/)
      end
    end

    it 'logs instance provisioning' do
      vm_log = bosh.ssh(deployment_name, Helpers::Environment::BROKER_JOB_NAME, 'sudo cat /var/vcap/sys/log/cf-redis-broker/cf-redis-broker.stdout.log')
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
      @service_instance = service_broker.provision_instance(service_name, service_plan_name)
      @predeprovision_timestamp = bosh.ssh(deployment_name, Helpers::Environment::BROKER_JOB_NAME, 'date +%s')

      service_plan = service_broker.service_plan(service_name, service_plan_name)
      service_broker.deprovision_instance(@service_instance, service_plan)
    end

    it 'logs instance deprovisioning' do
      vm_log = bosh.ssh(deployment_name, Helpers::Environment::BROKER_JOB_NAME, 'sudo cat /var/vcap/sys/log/cf-redis-broker/cf-redis-broker.stdout.log')
      contains_expected_log = drop_log_lines_before(@predeprovision_timestamp, vm_log).any? do |line|
        line.include?('Successfully deprovisioned Redis instance') &&
          line.include?('dedicated-vm') &&
          line.include?(@service_instance.id)
      end

      expect(contains_expected_log).to be true
    end
  end

  describe 'recreating instance' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service_name, service_plan_name)
      @binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
      @client = service_client_builder(@binding)
    end

    after(:all) do
      service_plan = service_broker.service_plan(service_name, service_plan_name)

      service_broker.unbind_instance(@binding, service_plan)
      service_broker.deprovision_instance(@service_instance, service_plan)
    end

    it 'retains data and keeps the same credentials after recreating the node' do
      @client.write('test_key', 'test_value')
      # Check if data has been written
      expect(@client.read('test_key')).to eql('test_value')

      # Restart all dedicated nodes
      bosh.recreate(deployment_name, 'dedicated-node')

      # Ensure data is intact on node
      expect(@client.read('test_key')).to eq('test_value')
    end
  end

  describe 'recycled instances' do
    before(:all) do
      @service_instances = allocate_all_instances!
      service_instance = @service_instances.pop

      service_binding = service_broker.bind_instance(service_instance, service_name, service_plan_name)
      @old_credentials = service_binding.credentials
      @old_client = service_client_builder(service_binding)

      @old_client.write('test_key', 'test_value')
      expect(@old_client.read('test_key')).to eq('test_value')

      host = service_binding.credentials[:host]

      @instance = bosh.instance(deployment_name, host)

      aof_contents = bosh.ssh(deployment_name, @instance,
                              'sudo cat /var/vcap/store/redis/appendonly.aof')
      expect(aof_contents).to include('test_value')

      @script_sha = @old_client.script_load('return 1')
      expect(@old_client.script_exists(@script_sha)).to be true

      @original_config_maxmem = @old_client.config.fetch('maxmemory-policy')
      @old_client.write_config('maxmemory-policy', 'allkeys-lru')
      expect(@old_client.config.fetch('maxmemory-policy')).to eql('allkeys-lru')
      expect(@old_client.config.fetch('maxmemory-policy')).to_not eql(@original_config_maxmem)

      service_plan = service_broker.service_plan(service_name, service_plan_name)
      service_broker.unbind_instance(service_binding, service_plan)
      service_broker.deprovision_instance(service_instance, service_plan)

      @service_instance = service_broker.provision_instance(service_name, service_plan_name)
      @service_binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
    end

    after(:all) do
      service_plan = service_broker.service_plan(service_name, service_plan_name)

      service_broker.unbind_instance(@service_binding, service_plan)
      service_broker.deprovision_instance(@service_instance, service_plan)

      @service_instances.each do |service_instance|
        service_broker.deprovision_instance(service_instance, service_plan)
      end
    end

    it 'cleans the aof file' do
      aof_contents = bosh.ssh(deployment_name, @instance,
                              'sudo cat /var/vcap/store/redis/appendonly.aof')
      expect(aof_contents).to_not include('test_value')
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
      @service_instance = service_broker.provision_instance(service_name, service_plan_name)
      @service_binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)

      new_client = service_client_builder(@service_binding)
      @infinite_loop_sha = new_client.script_load(LUA_INFINITE_LOOP)
      expect(new_client.script_exists(@infinite_loop_sha)).to be true

      Thread.new { @new_client.evalsha @infinite_loop_sha, 0 }
    end

    it 'successfully deprovisions' do
      service_plan = service_broker.service_plan(service_name, service_plan_name)

      service_broker.unbind_instance(@service_binding, service_plan)
      service_broker.deprovision_instance(@service_instance, service_plan)
    end
  end
end

def allocate_all_instances!
  max_instances = test_manifest['instance_groups'].select do |instance_group|
    instance_group['name'] == Helpers::Environment::DEDICATED_NODE_JOB_NAME
  end.first['instances']
  max_instances.times.map { service_broker.provision_instance(service_name, service_plan_name) }
end
