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
        broker_ssh.execute("sudo /var/vcap/bosh/bin/monit restart #{Helpers::Environment::BROKER_JOB_NAME}")
        expect(broker_ssh.wait_for_process_start(Helpers::Environment::BROKER_JOB_NAME)).to be true
      end

      it 'forwards logs' do
        expect { syslog_helper.get_line }.to eventually(include Helpers::Environment::BROKER_JOB_NAME).within 5
      end
    end

    context 'dedicated-node' do
      before do
        dedicated_node_ssh.execute('sudo /var/vcap/bosh/bin/monit restart redis')
        expect(dedicated_node_ssh.wait_for_process_start('redis')).to be true
      end

      it 'forwards logs' do
        expect { syslog_helper.get_line }.to eventually(include Helpers::Environment::DEDICATED_NODE_JOB_NAME).within 5
      end
    end
  end

  describe 'redis broker' do
    def service
      Helpers::Service.new(
        name: bosh_manifest.property('redis.broker.service_name'), 
        plan: 'shared-vm'
      )
    end

    before(:all) do
      broker_ssh.execute("sudo /var/vcap/bosh/bin/monit restart #{Helpers::Environment::BROKER_JOB_NAME}")
      expect(broker_ssh.wait_for_process_start(Helpers::Environment::BROKER_JOB_NAME)).to be true
    end

    it 'allows log access via bosh' do
      log_files_by_job = {
        Helpers::Environment::BROKER_JOB_NAME => %w[
          access.log
          cf-redis-broker.stderr.log
          cf-redis-broker.stdout.log
          error.log
          nginx.stderr.log
          nginx.stdout.log
          process-watcher.stderr.log
          process-watcher.stdout.log
        ]
      }
      log_files_by_job.each_pair do |job_name, log_files|
        expect(bosh_director.job_logfiles(job_name)).to include(*log_files)
      end
    end
  end

  describe 'dedicated redis process' do
    REDIS_SERVER_STARTED_PATTERN = 'Ready to accept connections'

    def service
      Helpers::Service.new(
        name: bosh_manifest.property('redis.broker.service_name'),
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
      service_plan = service_broker.catalog.service_plan(service.name, service.plan)

      service_broker.unbind_instance(@binding, service_plan)
      service_broker.deprovision_instance(@service_instance, service_plan)
      @log.info("Deprovisioned dedicated instance #{@host} for tests")
    end

    it 'logs to its local log file' do
      redis_log_file = '/var/vcap/sys/log/redis/redis.log'
      expect(count_from_log(dedicated_node_ssh, @redis_server_port_pattern, redis_log_file)).to be > 0
      expect(count_from_log(dedicated_node_ssh, REDIS_SERVER_STARTED_PATTERN, redis_log_file)).to be > 0
    end
  end
end

def count_from_log(ssh_target, pattern, log_file)
  output = ssh_target.execute(%(sudo grep -v grep #{log_file} | grep -c "#{pattern}"))
  Integer(output.strip)
end
