require 'yaml'

PROJECT_ROOT = File.join(File.dirname(__FILE__), '..', '..')
BROKER_SPEC_PATH = File.join(PROJECT_ROOT, 'jobs/cf-redis-broker/spec')
DEDICATED_NODE_SPEC_PATH = File.join(PROJECT_ROOT, 'jobs/dedicated-node/spec')

describe 'bosh specs' do
  describe 'broker' do
    subject { YAML.load_file(BROKER_SPEC_PATH) }

    it 'is configured expose redis.config_command as a bosh link' do
      expected_link = {
        'name' => 'redis_broker',
        'type' => 'redis_broker',
      }

      expect(subject['provides']).to include(expected_link)
    end
  end

  describe 'dedicated-node' do
    subject { YAML.load_file(DEDICATED_NODE_SPEC_PATH) }

    it 'is configured expose redis.config_command as a bosh link' do
      expected_link = {
        'name' => 'dedicated_node',
        'type' => 'redis',
      }

      expect(subject['provides']).to include(expected_link)
    end
  end
end
