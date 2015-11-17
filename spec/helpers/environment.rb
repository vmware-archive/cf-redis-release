require 'prof/environment/cloud_foundry'

require 'support/redis_service_broker'
require 'support/redis_service_client_builder'

module Helpers
  module Environment
    def environment
      @environment ||= begin
        options = {
          bosh_manifest_path: ENV.fetch('BOSH_MANIFEST') { File.join(ROOT, 'manifests/cf-redis-lite.yml') },
          bosh_service_broker_job_name: 'cf-redis-broker'
        }
        options[:bosh_target]          = ENV['BOSH_TARGET']   if ENV.key?('BOSH_TARGET')
        options[:bosh_username]        = ENV['BOSH_USERNAME'] if ENV.key?('BOSH_USERNAME')
        options[:bosh_password]        = ENV['BOSH_PASSWORD'] if ENV.key?('BOSH_PASSWORD')
        options[:ssh_gateway_host]     = ENV['BOSH_TARGET']   if ENV.key?('BOSH_TARGET')
        options[:ssh_gateway_username] = 'vcap'               if ENV.key?('BOSH_TARGET')
        options[:ssh_gateway_password] = 'c1oudc0w'           if ENV.key?('BOSH_TARGET')

        options[:use_proxy]            = ENV['USE_PROXY'] == 'true'
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

    def ssh_gateway
      environment.ssh_gateway
    end

    def broker_host
      bosh_manifest.job('cf-redis-broker').static_ips.first
    end

    def node_hosts
      bosh_manifest.job('dedicated-node').static_ips
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
  end
end
