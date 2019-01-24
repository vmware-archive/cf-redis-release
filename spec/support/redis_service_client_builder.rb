require 'support/redis_service_client'

module Support
  class RedisServiceClientBuilder
    def initialize(save_command:, config_command:, ssh_gateway:)
      @save_command   = save_command
      @config_command = config_command
      @ssh_gateway    = ssh_gateway
    end

    def build(binding)
      RedisServiceClient.new(
        binding: binding,
        save_command: save_command,
        config_command: config_command,
        ssh_gateway: ssh_gateway
      )
    end

    private

    attr_reader :save_command, :config_command, :ssh_gateway
  end
end
