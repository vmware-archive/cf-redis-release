# Copyright (c) 2014-2015 Pivotal Software, Inc.
# All rights reserved.
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
# USE OR OTHER DEALINGS IN THE SOFTWARE.
#

require 'net/ssh'
require 'net/ssh/gateway'
require 'net/scp'
require 'uri'

module Helpers
  class SshGateway
    def initialize(gateway_host:, gateway_username:, gateway_password: nil, gateway_private_key: nil, ssh_key: nil)
      @gateway_host = gateway_host
      @gateway_username = gateway_username
      @gateway_password = gateway_password
      @gateway_private_key = gateway_private_key
      @ssh_key = ssh_key
      @forwards = {}
    end

    def execute_on(host, cmd, options = {})
      user = options.fetch(:user, 'vcap')
      password = options.fetch(:password, 'c1oudc0w')
      run_as_root = options.fetch(:root, false)
      discard_stderr = options.fetch(:discard_stderr, false)

      cmd = "echo -e \"#{password}\\n\" | sudo -S #{cmd}" if run_as_root
      cmd << ' 2>/dev/null' if discard_stderr

      ssh_gateway_options = {
          password: password,
          verify_host_key: :never
      }

      if @ssh_key
        ssh_gateway_options[:key_data] = [@ssh_key]
      else
        ssh_gateway_options[:auth_methods] = [ 'password', 'publickey' ]
      end

      suppress_warnings do
        ssh_gateway.ssh(
            host,
            user,
            ssh_gateway_options,
            ) do |ssh|
          ssh.exec!(cmd)
        end
      end
    end

    def scp_to(host, local_path, remote_path, options = {})
      with_port_forwarded_to(host, 22) do |local_port|
        options[:port] = local_port
        options[:user] ||= 'vcap'
        options[:password] ||= 'c1oudc0w'
        Net::SCP.start('127.0.0.1', options.fetch(:user), options) do |scp|
          scp.upload! local_path, remote_path
        end
      end
    end

    def scp_from(host, remote_path, local_path, options = {})
      with_port_forwarded_to(host, 22) do |local_port|
        options[:port] = local_port
        options[:user] ||= 'vcap'
        options[:password] ||= 'c1oudc0w'
        Net::SCP.start('127.0.0.1', options.fetch(:user), options) do |scp|
          scp.download! remote_path, local_path
        end
      end
    end

    def with_port_forwarded_to(remote_host, remote_port, &block)
      ssh_gateway.open(remote_host, remote_port, &block)
    end

    private

    def ssh_agent
      @ssh_agent ||= Net::SSH::Authentication::Agent.connect
    end

    def gateway_host
      URI(@gateway_host).host || @gateway_host
    end

    def ssh_gateway
      opts = { verify_host_key: :never }
      if @gateway_private_key
        opts[:keys] = [@gateway_private_key]
      else
        opts[:password] = @gateway_password
      end

      @ssh_gateway ||= Net::SSH::Gateway.new(
          gateway_host,
          @gateway_username,
          opts
      )
    rescue Net::SSH::AuthenticationFailed
      message = [
          "Failed to connect to #{gateway_host}, with #{@gateway_username}:#{@gateway_password}.",
          "The ssh-agent has #{ssh_agent.identities.size} identities. Please either add a key, or correct password"
      ].join(' ')
      raise Net::SSH::AuthenticationFailed, message
    end

    def suppress_warnings
      original_verbosity = $VERBOSE
      $VERBOSE = nil
      result = yield
      $VERBOSE = original_verbosity
      return result
    end
  end
end
