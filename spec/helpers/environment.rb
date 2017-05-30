require 'prof/environment/cloud_foundry'

require 'support/redis_service_broker'
require 'support/redis_service_client_builder'
require 'helpers/bosh_cli_wrapper'

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
    fail "Must specify BOSH_MANIFEST environment variable" unless ENV.key?('BOSH_MANIFEST')

    BROKER_JOB_NAME = 'cf-redis-broker'
    DEDICATED_NODE_JOB_NAME = 'dedicated-node'

    def environment
      @environment ||= begin
        options = {
          bosh_manifest_path: ENV.fetch('BOSH_MANIFEST'),
          bosh_service_broker_job_name: BROKER_JOB_NAME
        }
        options[:bosh_target]       = ENV['BOSH_TARGET']              if ENV.key?('BOSH_TARGET')
        options[:bosh_username]     = ENV['BOSH_USERNAME']            if ENV.key?('BOSH_USERNAME')
        options[:bosh_password]     = ENV['BOSH_PASSWORD']            if ENV.key?('BOSH_PASSWORD')
        options[:bosh_ca_cert_path] = ENV['BOSH_CA_CERT']             if ENV.key?('BOSH_CA_CERT')
        options[:bosh_env_login]    = ENV['BOSH_ENV_LOGIN'] == 'true'

        if ENV.key?('BOSH_TARGET')
          options[:ssh_gateway_host]     = URI.parse(ENV['BOSH_TARGET']).host
          options[:ssh_gateway_username] = 'vcap'
          options[:ssh_gateway_password] = 'c1oudc0w'
        end

        if ENV.key?('JUMPBOX_HOST')
          options[:ssh_gateway_host]        = parse_host(ENV['JUMPBOX_HOST'])
          options[:ssh_gateway_username]    = ENV.fetch('JUMPBOX_USERNAME')
          options[:ssh_gateway_password]    = ENV['JUMPBOX_PASSWORD']         if ENV.key?('JUMPBOX_PASSWORD')
          options[:ssh_gateway_private_key] = ENV['JUMPBOX_PRIVATE_KEY']      if ENV.key?('JUMPBOX_PRIVATE_KEY')
        end

        options[:use_proxy] = ENV['USE_PROXY'] == 'true'
        Prof::Environment::CloudFoundry.new(options)
      end
    end

    def redis_service_broker
      Support::RedisServiceBroker.new(service_broker)
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
      BOSHCLIWrapper.new(bosh_manifest.deployment_name, BROKER_JOB_NAME, 0)
    end

    def dedicated_node_ssh
      BOSHCLIWrapper.new(bosh_manifest.deployment_name, DEDICATED_NODE_JOB_NAME, 0)
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

    def broker_host
      bosh_manifest.job(BROKER_JOB_NAME).static_ips.first
    end

    def node_hosts
      bosh_manifest.job(DEDICATED_NODE_JOB_NAME).static_ips
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

    def root_execute_on(ip, command)
      root_prompt = '[sudo] password for vcap: '
      root_prompt_length = root_prompt.length

      output = ssh_gateway.execute_on(ip, command, root: true)
      expect(output).not_to be_nil
      expect(output).to start_with(root_prompt)
      return output.slice(root_prompt_length, output.length - root_prompt_length)
    end

    private

    def parse_host(raw_host)
      host = raw_host
      host = 'http://' + host unless host.start_with? 'http'
      URI.parse(host).host
    end
  end
end
