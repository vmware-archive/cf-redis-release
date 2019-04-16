# frozen_string_literal: true

require 'system_spec_helper'

def bosh
  Helpers::Bosh2.new
end

describe 'nginx' do
  describe 'configuration' do
    CONFIG_PATH = '/var/vcap/jobs/cf-redis-broker/config/nginx.conf'

    def service_name
      test_manifest['properties']['redis']['broker']['service_name']
    end

    def service_plan_name
      'shared-vm'
    end

    let(:bucket_size) do
      if test_manifest['properties']['redis']['broker'].dig('nginx', 'bucket_size').nil?
        128
      else
        test_manifest['properties']['redis']['broker'].dig('nginx', 'bucket_size')
      end
    end

    before(:all) do
      @service_instance = service_broker.provision_instance(service_name, service_plan_name)
      @binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
    end

    after(:all) do
      service_plan = service_broker.service_plan(service_name, service_plan_name)

      service_broker.unbind_instance(@binding, service_plan)
      service_broker.deprovision_instance(@service_instance, service_plan)
    end

    it 'has the correct server_names_hash_bucket_size' do
      expect(bucket_size).to be > 0
      command = %(sudo grep "server_names_hash_bucket_size #{bucket_size}" #{CONFIG_PATH})
      result = bosh.ssh(deployment_name, "#{Helpers::Environment::BROKER_JOB_NAME}/0", command)
      expect(result.strip).not_to be_empty
    end
  end
end
