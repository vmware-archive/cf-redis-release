require 'system_spec_helper'
require 'support/redis_service_client'
require 'system/shared_examples/redis_instance'

require 'prof/external_spec/shared_examples/service'
require 'prof/marketplace_service'

describe 'shared plan' do
  def service
    Prof::MarketplaceService.new(
      name: bosh_manifest.property('redis.broker.service_name'),
      plan: 'shared-vm'
    )
  end

  # TODO do not manually run drain once bosh bug fixed
  let(:manually_drain) { '/var/vcap/jobs/cf-redis-broker/bin/drain' }

  it 'preserves data when recreating vms' do
    service_broker.provision_and_bind(service.name, service.plan) do |service_binding|
      service_client = service_client_builder(service_binding)
      service_client.write('test_key', 'test_value')
      expect(service_client.read('test_key')).to eq('test_value')

      # TODO do not manually run drain once bosh bug fixed
      bosh_director.stop(environment.bosh_service_broker_job_name, 0)
      host = service_binding.credentials.fetch(:host)
      ssh_gateway.execute_on(host, manually_drain, root: true)

      bosh_director.recreate_all([environment.bosh_service_broker_job_name])

      expect(service_client.read('test_key')).to eq('test_value')
    end
  end

  it_behaves_like 'a persistent cloud foundry service'

  let(:maxmemory) { bosh_manifest.property('redis.maxmemory') }

  describe 'redis configuration' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @service_binding  = service_broker.bind_instance(@service_instance)
    end

    after(:all) do
      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'has the correct maxclients' do
      service_client = service_client_builder(@service_binding)
      expect(service_client.config.fetch('maxclients')).to eq("10000")
    end

    it 'has the correct maxmemory' do
      service_client = service_client_builder(@service_binding)
      expect(service_client.config.fetch('maxmemory').to_i).to eq(maxmemory)
    end

    it 'runs correct version of redis' do
      service_client = service_client_builder(@service_binding)
      expect(service_client.info('redis_version')).to eq('3.2.1')
    end
  end

  describe 'pidfiles' do
    it 'do not appear in persistent storage' do
      host = @service_binding.credentials.fetch(:host)
      persisted_pids = ssh_gateway.execute_on(host, 'find /var/vcap/store/ -name "redis-server.pid" 2>/dev/null')
      expect(persisted_pids).to be_nil, "Actual output of find was: #{persisted_pids}"
    end

    it 'appear in ephemeral storage' do
      host = @service_binding.credentials.fetch(:host)
      ephemeral_pids = ssh_gateway.execute_on(host, 'find /var/vcap/sys/run/shared-instance-pidfiles/ -name *.pid 2>/dev/null')
      expect(ephemeral_pids).to_not be_nil
      expect(ephemeral_pids.lines.length).to eq(1), "Actual output of find was: #{ephemeral_pids}"
    end
  end

  context 'when redis related properties changed in the manifest' do
    before do
      bosh_manifest.set_property('redis.config_command', 'configalias')
      bosh_director.deploy
    end

    after do
      bosh_manifest.set_property('redis.config_command', 'configalias')
      bosh_director.deploy
    end

    it 'updates existing instances' do
      service_broker.provision_and_bind(service.name, service.plan) do |service_binding|
        redis_client_1 = service_client_builder(service_binding)
        redis_client_1.write('test', 'foobar')
        original_config_command = redis_client_1.config_command

        bosh_manifest.set_property('redis.config_command', 'newconfigalias')
        bosh_director.deploy

        redis_client_2 = service_client_builder(service_binding)
        new_config_command = redis_client_2.config_command
        expect(original_config_command).to_not eq(new_config_command)
        expect(redis_client_2.read('test')).to eq('foobar')
      end
    end
  end

  context 'service broker' do
    let(:admin_command_availability) do
      {
        'BGSAVE' => false,
        'BGREWRITEAOF' => false,
        'MONITOR' => false,
        'SAVE' => false,
        'DEBUG' => false,
        'SHUTDOWN' => false,
        'SLAVEOF' => false,
        'SYNC' => false,
        'CONFIG' => false
      }
    end

    it_behaves_like 'a redis instance'
  end

  context 'when repeatedly draining a redis instance' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @service_binding  = service_broker.bind_instance(@service_instance)
      @vm_ip            = @service_binding.credentials[:host]

      ps_output = ssh_gateway.execute_on(@vm_ip, 'ps aux | grep redis-serve[r]')
      expect(ps_output).not_to be_nil
      expect(ps_output.lines.length).to eq(1)

      drain_command = '/var/vcap/jobs/cf-redis-broker/bin/drain'
      root_execute_on(@vm_ip, drain_command)
      sleep 1

      ps_output = ssh_gateway.execute_on(@vm_ip, 'ps aux | grep redis-serve[r]')
      expect(ps_output).to be_nil

      root_execute_on(@vm_ip, '/var/vcap/bosh/bin/monit restart process-watcher')

      for _ in 0..45 do
        sleep 1

        monit_output = root_execute_on(@vm_ip, '/var/vcap/bosh/bin/monit summary | grep process-watcher | grep running')
        if !monit_output.strip.empty? then
          break
        end
      end

      monit_output = root_execute_on(@vm_ip, '/var/vcap/bosh/bin/monit summary | grep process-watcher | grep running')
      expect(monit_output.strip).not_to be_empty

      root_execute_on(@vm_ip, drain_command)
      sleep 1
    end

    after(:all) do
      root_execute_on(@vm_ip, '/var/vcap/bosh/bin/monit restart process-watcher')

      for _ in 0..45 do
        sleep 1

        monit_output = root_execute_on(@vm_ip, '/var/vcap/bosh/bin/monit summary | grep process-watcher | grep running')
        if !monit_output.strip.empty? then
          break
        end
      end

      monit_output = root_execute_on(@vm_ip, '/var/vcap/bosh/bin/monit summary | grep process-watcher | grep running')
      expect(monit_output.strip).not_to be_empty

      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'successfuly drained the redis instance' do
      ps_output = ssh_gateway.execute_on(@vm_ip, 'ps aux | grep redis-serve[r]')
      expect(ps_output).to be_nil
    end
  end

  def root_execute_on(ip, command)
    root_prompt = '[sudo] password for vcap: '
    root_prompt_length = root_prompt.length

    output = ssh_gateway.execute_on(ip, command, root: true)
    expect(output).not_to be_nil
    expect(output).to start_with(root_prompt)
    return output.slice(root_prompt_length, output.length - root_prompt_length)
  end
end
