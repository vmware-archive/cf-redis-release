require 'logger'
require 'system_spec_helper'
require 'rspec/eventually'
require 'helpers/service'

describe 'logging' do
  SYSLOG_FILE = "/var/log/syslog"

  describe 'syslog-forwarding' do
    let(:syslog_helper) { get_syslog_endpoint_helper }

    before do
      syslog_helper.drain
    end

    context 'cf-redis-broker' do
      before do
        bosh.ssh(deployment_name, Helpers::Environment::BROKER_JOB_NAME, "sudo /var/vcap/bosh/bin/monit restart #{Helpers::Environment::BROKER_JOB_NAME}")
        expect(bosh.wait_for_process_start(deployment_name, Helpers::Environment::BROKER_JOB_NAME, Helpers::Environment::BROKER_JOB_NAME)).to be true
      end

      it 'forwards logs' do
        expect { syslog_helper.get_line }.to eventually(include Helpers::Environment::BROKER_JOB_NAME).within 5
      end
    end

    context 'dedicated-node' do
      before do
        bosh.ssh(deployment_name, "#{Helpers::Environment::DEDICATED_NODE_JOB_NAME}/0", 'sudo /var/vcap/bosh/bin/monit restart redis')
        expect(bosh.wait_for_process_start(deployment_name, "#{Helpers::Environment::DEDICATED_NODE_JOB_NAME}/0", ('redis'))).to be true
      end

      it 'forwards logs' do
        expect { syslog_helper.get_line }.to eventually(include Helpers::Environment::DEDICATED_NODE_JOB_NAME).within 5
      end
    end
  end

  describe 'redis broker' do
    def service
      Helpers::Service.new(
        name: test_manifest['properties']['redis']['broker']['service_name'],
        plan: 'shared-vm'
      )
    end

    before(:all) do
      bosh.ssh(deployment_name, Helpers::Environment::BROKER_JOB_NAME, "sudo /var/vcap/bosh/bin/monit restart #{Helpers::Environment::BROKER_JOB_NAME}")
      expect(bosh.wait_for_process_start(deployment_name, Helpers::Environment::BROKER_JOB_NAME, Helpers::Environment::BROKER_JOB_NAME)).to be true
    end

    it 'allows log access via bosh' do
      expected_log_files = %w[
          access.log
          cf-redis-broker.stderr.log
          cf-redis-broker.stdout.log
          error.log
          nginx.stderr.log
          nginx.stdout.log
          process-watcher.stderr.log
          process-watcher.stdout.log
        ]

      log_paths = bosh.log_files(deployment_name, Helpers::Environment::BROKER_JOB_NAME)
      expect(log_paths.map(&:basename).map(&:to_s)).to include(*expected_log_files)
    end
  end

  describe 'dedicated redis process' do
    REDIS_SERVER_STARTED_PATTERN = 'Ready to accept connections'

    def service
      Helpers::Service.new(
        name: test_manifest['properties']['redis']['broker']['service_name'],
        plan: 'dedicated-vm'
      )
    end

    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @binding = service_broker.bind_instance(@service_instance, service.name, service.plan)
      @redis_server_port_pattern = "Running mode=.*, port=#{@binding.credentials[:port]}"

      @host = @binding.credentials[:host]
      @log = Logger.new(STDOUT)
      @log.info("Provisioned dedicated instance #{@host} for tests")
    end

    after(:all) do
      service_plan = service_broker.service_plan(service.name, service.plan)

      service_broker.unbind_instance(@binding, service_plan)
      service_broker.deprovision_instance(@service_instance, service_plan)
      @log.info("Deprovisioned dedicated instance #{@host} for tests")
    end

    it 'logs to its local log file' do
      redis_log_file = '/var/vcap/sys/log/redis/redis.log'
      expect(count_from_log(
                 deployment_name,
                 "#{Helpers::Environment::DEDICATED_NODE_JOB_NAME}/0",
                 @redis_server_port_pattern,
                 redis_log_file)).to be > 0
      expect(count_from_log(
                 deployment_name,
                 "#{Helpers::Environment::DEDICATED_NODE_JOB_NAME}/0",
                 REDIS_SERVER_STARTED_PATTERN,
                 redis_log_file)).to be > 0
    end
  end
end

def count_from_log(deployment_name, instance, pattern, log_file)
  output = bosh.ssh(deployment_name, instance, %(sudo grep -v grep #{log_file} | grep -c "#{pattern}"))
  Integer(output.strip)
end
