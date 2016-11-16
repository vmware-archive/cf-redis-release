require 'prof/environment/cloud_foundry'

require 'support/redis_service_broker'
require 'support/redis_service_client_builder'
require 'hula/bosh_director'
require 'logger'
require 'hula/command_runner'
require 'yaml'

module Helpers
  module Environment
    def environment
      @environment ||= begin
        options = {
          bosh_manifest_path: File.join(ROOT, RSpec.configuration.manifest_path),
          bosh_service_broker_job_name: 'cf-redis-broker'
        }
        options[:bosh_username]        = ENV['BOSH_USERNAME']               if ENV.key?('BOSH_USERNAME')
        options[:bosh_target]          = ENV['BOSH_TARGET']                 if ENV.key?('BOSH_TARGET')
        options[:bosh_password]        = ENV['BOSH_PASSWORD']               if ENV.key?('BOSH_PASSWORD')
        options[:ssh_gateway_host]     = URI.parse(ENV['BOSH_TARGET']).host if ENV.key?('BOSH_TARGET')
        options[:ssh_gateway_username] = 'vcap'                             if ENV.key?('BOSH_TARGET')
        options[:ssh_gateway_password] = 'c1oudc0w'                         if ENV.key?('BOSH_TARGET')

        FileUtils.mkdir_p(File.dirname(options[:bosh_manifest_path]))
        prepare_bosh_manifest options
        Prof::Environment::CloudFoundry.new(options)
      end
    end

    def prepare_bosh_manifest options
      bosh_manifest_path = options[:bosh_manifest_path]

      bosh_director = Hula::BoshDirector.new(
        target_url: options[:bosh_target] ||= "https://192.168.50.4:25555",
        username: options[:bosh_username] ||= "admin",
        password: options[:bosh_password] ||= "admin",
        manifest_path: nil,
        command_runner: Hula::CommandRunner.new,
        logger: Logger.new('/dev/null'))


      if ENV.key?('DEPLOYMENT_NAME')
        deployment_name = ENV['DEPLOYMENT_NAME']
      else
        deployment_name = "cf-redis-v346"
      end

      downloaded_manifest = bosh_director.download_manifest deployment_name

      File.open(bosh_manifest_path, "w") do |file|
        file.write(downloaded_manifest.to_yaml)
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
