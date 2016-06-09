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
    service_broker.provision_and_bind(service.name, service.plan) do |binding|
      service_client = service_client_builder(binding)
      service_client.write('test_key', 'test_value')
      expect(service_client.read('test_key')).to eq('test_value')

      # TODO do not manually run drain once bosh bug fixed
      bosh_director.stop(environment.bosh_service_broker_job_name, 0)
      host = binding.credentials.fetch(:host)
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
      @binding          = service_broker.bind_instance(@service_instance)
    end

    after(:all) do
      service_broker.unbind_instance(@binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'has the correct maxclients' do
      service_client = service_client_builder(@binding)
      expect(service_client.config.fetch('maxclients')).to eq("10000")
    end

    it 'has the correct maxmemory' do
      service_client = service_client_builder(@binding)
      expect(service_client.config.fetch('maxmemory').to_i).to eq(maxmemory)
    end

    it 'runs correct version of redis' do
      service_client = service_client_builder(@binding)
      expect(service_client.info('redis_version')).to eq('3.0.4')
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

      for _ in 0..30 do
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
      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'successfuly drained the redis instance' do
      ps_output = ssh_gateway.execute_on(@vm_ip, 'ps aux | grep redis-serve[r]')
      puts ps_output
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
