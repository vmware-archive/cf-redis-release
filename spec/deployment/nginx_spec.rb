# frozen_string_literal: true

require 'system_spec_helper'
require 'helpers/service'

describe 'nginx' do
  describe 'configuration' do
    CONFIG_PATH = '/var/vcap/jobs/cf-redis-broker/config/nginx.conf'

    def service
      Helpers::Service.new(
        name: test_manifest['properties']['redis']['broker']['service_name'],
        plan: 'shared-vm'
      )
    end

    let(:bucket_size) do
      if test_manifest['properties']['redis']['broker'].dig('nginx', 'bucket_size').nil?
        128
      else
        test_manifest['properties']['redis']['broker'].dig('nginx', 'bucket_size')
      end
    end

    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @binding = service_broker.bind_instance(@service_instance, service.name, service.plan)
    end

    after(:all) do
      service_plan = service_broker.catalog.service_plan(service.name, service.plan)

      service_broker.unbind_instance(@binding, service_plan)
      service_broker.deprovision_instance(@service_instance, service_plan)
    end

    it 'has the correct server_names_hash_bucket_size' do
      expect(bucket_size).to be > 0
      command = %(sudo grep "server_names_hash_bucket_size #{bucket_size}" #{CONFIG_PATH})
      result = bosh.ssh(deployment_name, "#{Helpers::Environment::DEDICATED_NODE_JOB_NAME}/0", command)
      expect(result.strip).not_to be_empty
    end
  end
end
