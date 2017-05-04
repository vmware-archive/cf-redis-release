require 'yaml'

PROJECT_ROOT = File.join(File.dirname(__FILE__), '..', '..')
BROKER_SPEC_PATH = File.join(PROJECT_ROOT, 'jobs/cf-redis-broker/spec')
DEDICATED_NODE_SPEC_PATH = File.join(PROJECT_ROOT, 'jobs/dedicated-node/spec')

describe 'bosh specs' do
  describe 'broker' do
    subject { YAML.load_file(BROKER_SPEC_PATH) }

    xit 'is configured expose redis.config_command as a bosh link' do
      expected_link = {
        'name' => 'redis_broker',
        'type' => 'redis',
        'properties' => ['redis.config_command'],
      }

      expect(subject['provides']).to include(expected_link)
    end

    it 'is configured to consume dedicated_node' do
      expected_consumer = {
        'name' => 'dedicated_node',
        'type' => 'redis',
      }

      expect(subject['consumes']).to include(expected_consumer)
    end
  end

  describe 'dedicated-node' do
    subject { YAML.load_file(DEDICATED_NODE_SPEC_PATH) }

    it 'is configured to provide a link' do
      expected_link = {
        'name' => 'dedicated_node',
        'type' => 'redis',
        'properties' => ['redis.broker.dedicated_port'],
      }

      expect(subject['provides']).to include(expected_link)
    end
  end
end
