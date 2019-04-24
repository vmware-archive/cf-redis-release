require 'support/redis_service_broker'
require 'helpers/service_broker'
require 'helpers/json_http_client'
require 'helpers/ssh_gateway'
require 'support/redis_service_client_builder'
require 'helpers/utilities'

class FilteredStderr < StringIO
  def write(value)
    return if value.include? 'Object#timeout is deprecated'

    return if value == "\n"

    STDERR.write value
  end
end

module Helpers
  module Environment
    fail 'Must specify BOSH_MANIFEST environment variable' unless ENV.key?('BOSH_MANIFEST')
    fail 'Must specify SYSLOG_TEST_ENDPOINT environment variable' unless ENV.key?('SYSLOG_TEST_ENDPOINT')

    BROKER_JOB_NAME = 'cf-redis-broker'
    DEDICATED_NODE_JOB_NAME = 'dedicated-node'


    def redis_service_broker
      Support::RedisServiceBroker.new(service_broker, test_manifest['properties']['redis']['broker']['service_name'])
    end

    def service_broker
      @service_broker ||= begin
        bosh_manifest_yaml = File.read(ENV.fetch('BOSH_MANIFEST'))

        @manifest_hash = YAML.load(bosh_manifest_yaml)
        if ENV.key?('BOSH_ENVIRONMENT')
          @ssh_gateway_host = URI.parse(ENV['BOSH_ENVIRONMENT']).host
          @ssh_gateway_username = 'vcap'
          @ssh_gateway_password = 'c1oudc0w'
        end

        if ENV.key?('JUMPBOX_HOST')
          @ssh_gateway_host = parse_host(ENV['JUMPBOX_HOST'])
          @ssh_gateway_username = ENV.fetch('JUMPBOX_USERNAME')
          @ssh_gateway_password = ENV['JUMPBOX_PASSWORD'] if ENV.key?('JUMPBOX_PASSWORD')
          @ssh_gateway_private_key = ENV['JUMPBOX_PRIVATE_KEY_PATH'] if ENV.key?('JUMPBOX_PRIVATE_KEY_PATH')
        end

        broker_registrar_properties = begin
          job = @manifest_hash.fetch('instance_groups').detect { |j| j.fetch('name') == 'broker-registrar' }
          if job.nil?
            # for colocated errands, the errand's instance group might not exist
            @manifest_hash.fetch('properties').fetch('broker')
          else
            job.fetch('properties').fetch('broker')
          end
        end

        Helpers::ServiceBroker.new(
          url: URI::HTTPS.build(host: broker_registrar_properties.fetch('host')),
          username: broker_registrar_properties.fetch('username'),
          password: broker_registrar_properties.fetch('password'),
          http_client: Helpers::HttpJsonClient.new,
          broker_api_version: '2.13'
        )
      end
    end

    def bosh
      Helpers::Bosh2.new
    end

    def get_syslog_endpoint_helper
      syslog_endpoint = URI.parse(ENV.fetch('SYSLOG_TEST_ENDPOINT'))
      gateway_executor = Utilities::GatewayExecutor.new(syslog_endpoint.host,
                                                        syslog_endpoint.port,
                                                        get_jumpbox_gateway_options)
      Utilities::SyslogEndpointHelper.new(syslog_endpoint.host,
                                          syslog_endpoint.port,
                                          gateway_executor)
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


    # net-ssh makes a deprecated call to `timeout`. We ignore these messages
    # because they pollute logs.
    # After using the filtered stderr we ensure to reassign the original stderr
    # stream.
    def ssh_gateway
      opts = {
        gateway_host: @ssh_gateway_host,
        gateway_username: @ssh_gateway_username,
      }

      if @ssh_gateway_private_key
        opts[:gateway_private_key] = @ssh_gateway_private_key
      else
        opts[:gateway_password] = @ssh_gateway_password
      end


      gateway = Helpers::SshGateway.new(opts)

      def gateway.execute_on(*args, &block)
        original_stderr = $stderr
        $stderr = FilteredStderr.new
        super
      ensure
        $stderr = original_stderr
      end

      def gateway.scp_to(*args, &block)
        original_stderr = $stderr
        $stderr = FilteredStderr.new
        super
      ensure
        $stderr = original_stderr
      end

      gateway
    end

    def broker_backend_port
      test_manifest['properties']['redis'].fetch('broker').fetch('backend_port')
    end

    def agent_backend_port
      test_manifest['properties']['redis'].fetch('agent').fetch('backend_port')
    end

    def service_client_builder(binding)
      Support::RedisServiceClientBuilder.new(
        ssh_gateway: ssh_gateway,
        save_command: bosh.manifest(deployment_name)['properties']['redis']['save_command'],
        config_command: bosh.manifest(deployment_name)['properties']['redis']['config_command']
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
