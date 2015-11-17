require 'redis'

module Support
  class RedisServiceClient
    def initialize(binding:, save_command:, config_command:, ssh_gateway:)
      @binding = binding
      @save_command = save_command
      @config_command = config_command
      @ssh_gateway = ssh_gateway
    end

    def write(key, value)
      client do |redis|
        redis.set(key, value)
      end
    end

    def read(key)
      client do |redis|
        redis.get(key)
      end
    end

    def info(key)
      client do |redis|
        redis.info.fetch(key)
      end
    end

    def aof_contents
      ssh_gateway.execute_on(host, 'cat /var/vcap/store/redis/appendonly.aof').to_s
    end

    def config
      Hash[client { |redis| redis.config('get', '*').each_slice(2).to_a }]
    end

    def write_config(key, value)
      client do |redis|
        redis.config('set', key, value)
      end
    end

    def run(command)
      client do |redis|
        redis.public_send(command)
      end
    end

    attr_reader :save_command, :config_command

    private

    attr_reader :binding, :ssh_gateway

    def client
      ssh_gateway.with_port_forwarded_to(host, port) do |forwarding_port|
        options = credentials.merge(
          'host' => '127.0.0.1',
          'port' => forwarding_port,
          'timeout' => 30,
          'reconnect_attempts' => 5
        )

        client = Redis.new(options).tap do |redis|
          redis.client.instance_variable_set(:@command_map, config: config_command, save: save_command)
        end

        return yield client
      end
    end

    def host
      credentials.fetch(:host)
    end

    def port
      credentials.fetch(:port)
    end

    def credentials
      binding.credentials
    end
  end
end
