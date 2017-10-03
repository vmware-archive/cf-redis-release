require 'json'
require 'yaml'
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
        service_name: p-redis-v431
        service_id: service_uuid
        shared_vm_plan_id: shared_vm_plan_uuid
        dedicated_vm_plan_id: dedicated_vm_plan_uuid
        service_instance_limit: 5
        auth:
          password: password
          username: username
  BROKER_MINIMUM_MANIFEST
  BROKER_LINKS = {
    'dedicated_node' => {
      'instances' => [
        {'address' => '10.0.10.5'},
        {'address' => '10.0.10.6'},
        {'address' => '10.0.10.7'}
      ],
      'properties' => {}
    }
  }

  context 'when redis.broker.dedicated_nodes property is not empty' do
    it 'templates the dedicated nodes using addresses from this property' do
      manifest = generate_manifest(BROKER_MINIMUM_MANIFEST) do |m|
        m['properties']['redis']['broker']['dedicated_nodes'] = [
          '10.0.8.109', '10.0.8.110', '10.0.8.112'
        ]
      end
      actual_template = render_template(BROKER_CONFIG_TEMPLATE_PATH, BROKER_JOB_NAME, manifest, BROKER_LINKS)
      expect(YAML.load(actual_template)['redis']['dedicated']['nodes']).to eq(
        ['10.0.8.109', '10.0.8.110', '10.0.8.112']
      )
    end
  end

  context 'when redis.broker.dedicated_nodes property is empty' do
    it 'templates the dedicated nodes using addresses from dedicated_node link' do
      manifest = generate_manifest(BROKER_MINIMUM_MANIFEST)
      actual_template = render_template(BROKER_CONFIG_TEMPLATE_PATH, BROKER_JOB_NAME, manifest, BROKER_LINKS)
      expect(YAML.load(actual_template)['redis']['dedicated']['nodes']).to eq(
        ['10.0.10.5', '10.0.10.6', '10.0.10.7']
      )
    end
    context 'when the link returns non-IPv4 addresses' do
      it 'fails to template' do
        manifest = generate_manifest(BROKER_MINIMUM_MANIFEST)
        BROKER_LINKS_HOSTNAMES = {
          'dedicated_node' => {
            'instances' => [
              {'address' => 'instance-id-1.dedicated-node.redis-z1.cf-cfapps-io2-redis.bosh'},
              {'address' => 'instance-id-10.dedicated-node.redis-z1.cf-cfapps-io2-redis.bosh'},
              {'address' => 'instance-id-11.dedicated-node.redis-z1.cf-cfapps-io2-redis.bosh'}
            ],
            'properties' => {}
          }
        }
        expect { render_template(BROKER_CONFIG_TEMPLATE_PATH, BROKER_JOB_NAME, manifest, BROKER_LINKS_HOSTNAMES)}.to raise_error('The broker only supports IP addresses for dedicated nodes')
      end
    end
  end
end
