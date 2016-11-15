require 'prof/environment/cloud_foundry'

require 'support/redis_service_broker'
require 'support/redis_service_client_builder'
require 'yaml'

module Helpers
  module Environment
    def environment
      @environment ||= begin
        options = {
          bosh_manifest_path: ENV.fetch('BOSH_MANIFEST') { File.join(ROOT, 'manifests/cf-redis-lite.yml') },
          bosh_service_broker_job_name: 'cf-redis-broker'
        }
        options[:bosh_username]        = ENV['BOSH_USERNAME']               if ENV.key?('BOSH_USERNAME')
        options[:bosh_target]          = ENV['BOSH_TARGET']                 if ENV.key?('BOSH_TARGET')
        options[:bosh_password]        = ENV['BOSH_PASSWORD']               if ENV.key?('BOSH_PASSWORD')
        options[:ssh_gateway_host]     = URI.parse(ENV['BOSH_TARGET']).host if ENV.key?('BOSH_TARGET')
        options[:ssh_gateway_username] = 'vcap'                             if ENV.key?('BOSH_TARGET')
        options[:ssh_gateway_password] = 'c1oudc0w'                         if ENV.key?('BOSH_TARGET')

        prepare_bosh_manifest
        Prof::Environment::CloudFoundry.new(options)
      end
    end

    def prepare_bosh_manifest options
      bosh_manifest_path = ENV.fetch('BOSH_MANIFEST')
      provided_manifest = YAML.load_file(bosh_manifest_path) { File.join(ROOT, 'manifests/cf-redis-lite.yml') })
      bosh_director = BoshDirector.new(
        target_url: options[:bosh_target],
        username: options[:bosh_username],
        password: options[:bosh_password],
        manifest_path: nil,
        command_runner: CommandRunner.new,
        logger: nil)
      downloaded_manifest = bosh_director.downloaded_manifest

      release = provided_manifest["releases"].select do |object|
        object["name"] == "cf-redis"
      end.first

      downloaded_release = downloaded_manifest["releases"].select do |key, value|
        key == "cf-redis"
      end.first

      release["version"] = downloaded_release["version"]

      File.open(bosh_manifest_path) do |file|
        file.write(provided_manifest.to_yaml)
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

    def service_client_builder(service_binding)
      Support::RedisServiceClientBuilder.new(
        ssh_gateway:    ssh_gateway,
        save_command:   bosh_manifest.property('redis.save_command'),
        config_command: bosh_manifest.property('redis.config_command')
      ).build(service_binding)
    end
  end
end
