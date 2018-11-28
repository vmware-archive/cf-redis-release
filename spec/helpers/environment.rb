require 'prof/environment/cloud_foundry'

require 'support/redis_service_broker'
require 'support/redis_service_client_builder'
require 'helpers/bosh_cli_wrapper'
require 'helpers/utilities'

class FilteredStderr < StringIO
  def write value
    if value.include? "Object#timeout is deprecated"
      return
    end

    if value == "\n"
      return
    end

    STDERR.write value
  end
end

module Helpers
  module Environment
    fail 'Must specify BOSH_MANIFEST environment variable' unless ENV.key?('BOSH_MANIFEST')
    fail 'Must specify SYSLOG_TEST_ENDPOINT environment variable' unless ENV.key?('SYSLOG_TEST_ENDPOINT')

    BROKER_JOB_NAME = 'cf-redis-broker'
    DEDICATED_NODE_JOB_NAME = 'dedicated-node'

    def environment
      @environment ||= begin
        options = {
          bosh_manifest_path: ENV.fetch('BOSH_MANIFEST'),
          bosh_service_broker_job_name: BROKER_JOB_NAME
        }
        options[:bosh_target]        = ENV['BOSH_ENVIRONMENT']         if ENV.key?('BOSH_ENVIRONMENT')
        options[:bosh_username]      = ENV['BOSH_USERNAME']            if ENV.key?('BOSH_USERNAME')
        options[:bosh_password]      = ENV['BOSH_PASSWORD']            if ENV.key?('BOSH_PASSWORD')
        options[:bosh_ca_cert_path]  = ENV['BOSH_CA_CERT_PATH']        if ENV.key?('BOSH_CA_CERT_PATH')
        options[:bosh_env_login]     = ENV['BOSH_ENV_LOGIN'] == 'true'
        options[:broker_api_version] = '2.13'

        if ENV.key?('BOSH_ENVIRONMENT')
          options[:ssh_gateway_host]     = URI.parse(ENV['BOSH_ENVIRONMENT']).host
          options[:ssh_gateway_username] = 'vcap'
          options[:ssh_gateway_password] = 'c1oudc0w'
        end

        options.merge! get_jumpbox_gateway_options

        options[:use_proxy] = ENV['USE_PROXY'] == 'true'
        Prof::Environment::CloudFoundry.new(options)
      end
    end

    def get_jumpbox_gateway_options
      options = {}
      if ENV.key?('JUMPBOX_HOST')
        options[:ssh_gateway_host]        = parse_host(ENV['JUMPBOX_HOST'])
        options[:ssh_gateway_username]    = ENV.fetch('JUMPBOX_USERNAME')
        options[:ssh_gateway_password]    = ENV['JUMPBOX_PASSWORD']         if ENV.key?('JUMPBOX_PASSWORD')
        options[:ssh_gateway_private_key] = ENV['JUMPBOX_PRIVATE_KEY_PATH'] if ENV.key?('JUMPBOX_PRIVATE_KEY_PATH')
      end
      options
    end

    def redis_service_broker
      Support::RedisServiceBroker.new(service_broker, bosh_manifest.property('redis.broker.service_name'))
    end

    def service_broker
      environment.service_broker
    end

    def bosh_manifest
      environment.bosh_manifest
    end

    def bosh_director
      environment.bosh_director
    end

    def broker_ssh
      BOSH::SSH.new(bosh_manifest.deployment_name, BROKER_JOB_NAME, 0)
    end

    def dedicated_node_ssh
      BOSH::SSH.new(bosh_manifest.deployment_name, DEDICATED_NODE_JOB_NAME, 0)
    end

    def instance_ssh(host_ip)
      instance_group, instance_id = BOSH::Deployment.new(bosh_manifest.deployment_name).instance(host_ip)
      BOSH::SSH.new(bosh_manifest.deployment_name, instance_group, instance_id)
    end

    def get_syslog_endpoint_helper
      syslog_endpoint = URI.parse(ENV.fetch('SYSLOG_TEST_ENDPOINT'))
      gateway_executor = Utilities::GatewayExecutor.new(syslog_endpoint.host, syslog_endpoint.port, get_jumpbox_gateway_options)
      Utilities::SyslogEndpointHelper.new(syslog_endpoint.host, syslog_endpoint.port, gateway_executor)
    end

    # net-ssh makes a deprecated call to `timeout`. We ignore these messages
    # because they pollute logs.
    # After using the filtered stderr we ensure to reassign the original stderr
    # stream.
    def ssh_gateway
      gateway = environment.ssh_gateway
      def gateway.execute_on(*args, &block)
        begin
          original_stderr = $stderr
          $stderr = FilteredStderr.new
          super
        ensure
          $stderr = original_stderr
        end
      end

      def gateway.scp_to(*args, &block)
        begin
          original_stderr = $stderr
          $stderr = FilteredStderr.new
          super
        ensure
          $stderr = original_stderr
        end
      end

      gateway
    end

    def broker_backend_port
      bosh_manifest.property('redis').fetch('broker').fetch('backend_port')
    end

    def agent_backend_port
      bosh_manifest.property('redis').fetch('agent').fetch('backend_port')
    end

    def service_client_builder(binding)
      Support::RedisServiceClientBuilder.new(
        ssh_gateway:    ssh_gateway,
        save_command:   bosh_manifest.property('redis.save_command'),
        config_command: bosh_manifest.property('redis.config_command')
      ).build(binding)
    end

    private

    def parse_host(raw_host)
      host = raw_host
      host = 'http://' + host unless host.start_with? 'http'
      URI.parse(host).host
    end
  end
end
