require 'system_spec_helper'

require 'prof/external_spec/shared_examples/deployment'
require 'prof/external_spec/shared_examples/service_broker'

describe 'logging' do
  let(:log_files_by_job) {
    {
      'cf-redis-broker' => [
        'access.log',
        'cf-redis-broker.stderr.log',
        'cf-redis-broker.stdout.log',
        'error.log',
        'nginx.stderr.log',
        'nginx.stdout.log',
        'process-watcher.stderr.log',
        'process-watcher.stdout.log',
        'route-registrar.stdout.log',
        'route-registrar.stderr.log',
      ]
    }
  }

  it_behaves_like 'a deployment' # log files in /var/vcap/sys/log
  it_behaves_like 'a service broker' # logs to syslog

  describe 'redis broker' do
    def service
      Prof::MarketplaceService.new(
        name: bosh_manifest.property('redis.broker.service_name'),
        plan: 'shared-vm'
      )
    end

    let(:shared_node_ip) { @binding.credentials[:host] }

    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @binding          = service_broker.bind_instance(@service_instance)
    end

    after(:all) do
      service_broker.unbind_instance(@binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'logs broker startup to syslog' do
      find_log_line_cmd = 'grep -c "redis-broker.Starting CF Redis broker" /var/log/syslog'

      result = root_execute_on(shared_node_ip, find_log_line_cmd)
      expect(result).not_to be_nil
      redis_server_start_count = Integer(result.strip)
      expect(redis_server_start_count).to be > 0
    end
  end

  describe 'dedicated redis process' do
    def service
      Prof::MarketplaceService.new(
        name: bosh_manifest.property('redis.broker.service_name'),
        plan: 'dedicated-vm'
      )
    end

    let(:redis_server_start_pattern) { "Server started, Redis version" }
    let(:redis_server_accept_conn_pattern) { "The server is now ready to accept connections on port #{@binding.credentials[:port]}" }
    let(:dedicated_node_ip) { @binding.credentials[:host] }

    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @binding          = service_broker.bind_instance(@service_instance)
    end

    after(:all) do
      service_broker.unbind_instance(@binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'logs to syslog' do
      root_prompt = "[sudo] password for vcap:"

      result = ssh_gateway.execute_on(dedicated_node_ip, "grep -c '#{redis_server_start_pattern}' /var/log/syslog", root: true)[root_prompt.length..-1]
      redis_server_start_count = Integer(result.strip)
      expect(redis_server_start_count).to be > 0
      result = ssh_gateway.execute_on(dedicated_node_ip, "grep -c '#{redis_server_accept_conn_pattern}' /var/log/syslog", root: true)[root_prompt.length..-1]
      redis_server_accept_conn_count = Integer(result.strip)
      expect(redis_server_accept_conn_count).to be > 0
    end

    it 'logs to its local log file' do
      local_log_file = "/var/vcap/sys/log/redis/redis.log"

      result = ssh_gateway.execute_on(dedicated_node_ip, "grep -c '#{redis_server_start_pattern}' #{local_log_file}")
      redis_server_start_count = Integer(result.strip)
      expect(redis_server_start_count).to be > 0
      result = ssh_gateway.execute_on(dedicated_node_ip, "grep -c '#{redis_server_accept_conn_pattern}' #{local_log_file}")
      redis_server_accept_conn_count = Integer(result.strip)
      expect(redis_server_accept_conn_count).to be > 0
    end
  end
end
