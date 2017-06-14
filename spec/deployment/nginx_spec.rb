require 'system_spec_helper'

describe 'nginx' do
  describe 'configuration' do
    CONFIG_PATH = "/var/vcap/jobs/cf-redis-broker/config/nginx.conf"

    def service
      Prof::MarketplaceService.new(
        name: bosh_manifest.property('redis.broker.service_name'),
        plan: 'shared-vm'
      )
    end

    let(:bucket_size) do
      if bosh_manifest.property('redis.broker').dig('nginx', 'bucket_size').nil?
        128
      else
        bosh_manifest.property('redis.broker').dig('nginx', 'bucket_size')
      end
    end

    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @binding = service_broker.bind_instance(@service_instance)
    end

    after(:all) do
      service_broker.unbind_instance(@binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'has the correct server_names_hash_bucket_size' do
      expect(bucket_size).to be > 0
      command = %Q{sudo grep "server_names_hash_bucket_size #{bucket_size}" #{CONFIG_PATH}}
      result = dedicated_node_ssh.execute(command)
      expect(result.strip).not_to be_empty
    end
  end
end
