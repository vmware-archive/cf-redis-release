require 'net/http'
require 'uri'
require 'timeout'

module Helpers
  module Utilities
    def drop_log_lines_before(time, log_lines)
      log_lines.lines.drop_while do |log_line|
        log_is_earlier?(log_line, time)
      end
    end

    private

    def log_is_earlier?(log_line, timestamp)
      match = log_line.scan( /\{.*\}$/ ).first

      return true if match.nil?

      begin
        json_log = JSON.parse(match)
      rescue JSON::ParserError
        return true
      end

      log_timestamp = json_log["timestamp"].to_i
      log_timestamp < timestamp.to_i
    end

    class SyslogEndpointHelper
      TEN_MILLISECONDS = 0.01
      FIVE_MINUTES = 60 * 5

      def initialize(syslog_host, syslog_port, gateway_executor)
        @gateway_executor = gateway_executor
      end

      def get_line
        @gateway_executor.exec!(Proc.new do |host, port|
          Net::HTTP.get(URI.parse("http://#{host}:#{port}"))
        end)
      end

      def drain
        Timeout::timeout(FIVE_MINUTES) {
          while true do
            return if get_line.include? 'no logs available'
            sleep TEN_MILLISECONDS
          end
        }
      end
    end

    class GatewayExecutor
      def initialize(host, port, gateway_opts = nil)
        @host = host
        @port = port
        @gateway_opts = gateway_opts
      end

      def setup_gateway_forwarding
        @_gateway ||= begin
          gateway_private_key = @gateway_opts[:ssh_gateway_private_key]
          opts = {}
          if !gateway_private_key.nil?
            opts[:keys] = [gateway_private_key]
          else
            opts[:password] = @gateway_opts[:ssh_gateway_password]
          end
          Net::SSH::Gateway.new(
            @gateway_opts[:ssh_gateway_host],
            @gateway_opts[:ssh_gateway_username],
            opts
          )
        end
        @_local_port ||= @_gateway.open(@host, @port)
      end

      def exec!(func)
        return func.call(@host, @port) if @gateway_opts.nil?
        func.call('127.0.0.1', setup_gateway_forwarding)
      end
    end
  end
end
