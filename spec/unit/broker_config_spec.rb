require 'json'
require 'yaml'
require 'bosh/template/renderer'
require 'helpers/unit_spec_utilities'

include Helpers::Utilities

RSpec.describe 'broker config' do
  BROKER_CONFIG_TEMPLATE_PATH = 'jobs/cf-redis-broker/templates/broker.yml.erb'
  BROKER_JOB_NAME = 'cf-redis-broker'
  BROKER_MINIMUM_MANIFEST = <<~BROKER_MINIMUM_MANIFEST
  instance_groups:
  - name: cf-redis-broker
    jobs:
    - name: cf-redis-broker
  properties:
    redis:
      broker:
        service_name: p-redis-v430
        service_id: service_uuid
        shared_vm_plan_id: shared_vm_plan_uuid
        dedicated_vm_plan_id: dedicated_vm_plan_uuid
        dedicated_nodes:
        - 10.0.8.109
        - 10.0.8.110
        - 10.0.8.112
        service_instance_limit: 5
        auth:
          password: password
          username: username
  BROKER_MINIMUM_MANIFEST

  it 'templates the dedicated nodes addresses' do
    manifest = generate_manifest(BROKER_MINIMUM_MANIFEST)
    actual_template = render_template(BROKER_CONFIG_TEMPLATE_PATH, BROKER_JOB_NAME, manifest)
    expect(YAML.load(actual_template)['redis']['dedicated']['nodes']).to eq(
      ['10.0.8.109', '10.0.8.110', '10.0.8.112']
    )
  end

  context 'when the dedicated nodes addresses are not IP addresses' do
    let(:manifest) do
      generate_manifest(BROKER_MINIMUM_MANIFEST) do |m|
        m['properties']['redis']['broker']['dedicated_nodes'] = [
          'instance-id-1.dedicated-node.redis-z1.cf-cfapps-io2-redis.bosh',
          'instance-id-2.dedicated-node.redis-z1.cf-cfapps-io2-redis.bosh',
          'instance-id-50.dedicated-node.redis-z1.cf-cfapps-io2-redis.bosh'
        ]
      end
    end
    it 'fails to template' do
      expect { render_template(BROKER_CONFIG_TEMPLATE_PATH, BROKER_JOB_NAME, manifest)}.to raise_error('The broker only supports IP addresses for dedicated nodes')
    end
  end

end
