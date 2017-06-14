require 'logger'
require 'system_spec_helper'

describe 'logging' do
  SYSLOG_FILE = "/var/log/syslog"

  describe 'redis broker' do
    def service
      Prof::MarketplaceService.new(
        name: bosh_manifest.property('redis.broker.service_name'),
        plan: 'shared-vm'
      )
    end

    before(:all) do
      broker_ssh.execute("sudo /var/vcap/bosh/bin/monit restart #{Helpers::Environment::BROKER_JOB_NAME}")
      expect(broker_ssh.wait_for_process_start(Helpers::Environment::BROKER_JOB_NAME)).to be true
    end

    it 'logs broker startup to syslog' do
      redis_server_starting_pattern = "redis-broker.Starting CF Redis broker"
      expect(count_from_log(broker_ssh, redis_server_starting_pattern, SYSLOG_FILE)).to be > 0
    end

    it 'logs to syslog' do
      nginx_pattern = "Cf#{environment.service_broker_name.capitalize}BrokerNginxAccess"
      expect(count_from_log(broker_ssh, nginx_pattern, SYSLOG_FILE)).to be > 0
    end

    it 'allows log access via bosh' do
      log_files_by_job = {
        Helpers::Environment::BROKER_JOB_NAME => [
          'access.log',
          'cf-redis-broker.stderr.log',
          'cf-redis-broker.stdout.log',
          'error.log',
          'nginx.stderr.log',
          'nginx.stdout.log',
          'process-watcher.stderr.log',
          'process-watcher.stdout.log',
        ]
      }
      log_files_by_job.each_pair do |job_name, log_files|
        expect(bosh_director.job_logfiles(job_name)).to include(*log_files)
      end
    end
  end

  describe 'dedicated redis process' do
    REDIS_SERVER_STARTED_PATTERN = "Server started, Redis version"

    def service
      Prof::MarketplaceService.new(
        name: bosh_manifest.property('redis.broker.service_name'),
        plan: 'dedicated-vm'
      )
    end

    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @binding = service_broker.bind_instance(@service_instance)
      @redis_server_accept_conn_pattern = "The server is now ready to accept connections on port #{@binding.credentials[:port]}"

      @host = @binding.credentials[:host]
      @log = Logger.new(STDOUT)
      @log.info("Provisioned dedicated instance #{@host} for tests")
    end

    after(:all) do
      service_broker.unbind_instance(@binding)
      service_broker.deprovision_instance(@service_instance)
      @log.info("Deprovisioned dedicated instance #{@host} for tests")
    end

    it 'logs to syslog' do
      expect(count_from_log(dedicated_node_ssh, REDIS_SERVER_STARTED_PATTERN, SYSLOG_FILE)).to be > 0
      expect(count_from_log(dedicated_node_ssh, @redis_server_accept_conn_pattern, SYSLOG_FILE)).to be > 0
    end

    it 'logs to its local log file' do
      redis_log_file = "/var/vcap/sys/log/redis/redis.log"
      expect(count_from_log(dedicated_node_ssh, REDIS_SERVER_STARTED_PATTERN, redis_log_file)).to be > 0
      expect(count_from_log(dedicated_node_ssh, @redis_server_accept_conn_pattern, redis_log_file)).to be > 0
    end
  end
end

def count_from_log(ssh_target, pattern, log_file)
  output = ssh_target.execute(%Q{sudo grep -c "#{pattern}" #{log_file}})
  Integer(output.strip)
end
