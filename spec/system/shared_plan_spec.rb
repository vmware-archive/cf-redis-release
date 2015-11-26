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
end
