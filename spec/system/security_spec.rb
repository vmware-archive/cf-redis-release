require 'system_spec_helper'

require 'socket'
require 'timeout'
require 'prof/ssl/cipher_set'

describe 'security' do
  describe 'the broker' do
    it 'uses latest version of nginx' do
      output = ssh_gateway.execute_on(broker_host, '/var/vcap/packages/nginx/sbin/nginx -v').strip
      expect(output).to eql('nginx version: nginx/1.8.0')
    end

    it 'does not listen publicly on the backend_port' do
      netstat_output = ssh_gateway.execute_on(broker_host, "netstat -l | grep #{broker_backend_port}")
      expect(netstat_output.lines.count).to eq(1)
      expect(netstat_output).to include("localhost:#{broker_backend_port}")
    end
  end

  describe 'the agents' do
    it 'uses latest version of nginx' do
      output = ssh_gateway.execute_on(node_hosts.first, '/var/vcap/packages/nginx/sbin/nginx -v').strip
      expect(output).to eql('nginx version: nginx/1.8.0')
    end

    it 'only supports HTTPS with restricted ciphers' do
      agent_url = "https://#{node_hosts.first}"
      expect(agent_url).to only_support_ssl_with_cipher_set(Prof::SSL::CipherSet::PIVOTAL_MODERN).with_proxy(environment.http_proxy)
    end

    it 'does not listen publicly on the backend_port' do
      netstat_output = ssh_gateway.execute_on(node_hosts.first, "netstat -l | grep #{agent_backend_port}")
      expect(netstat_output.lines.count).to eq(1)
      expect(netstat_output).to include("localhost:#{agent_backend_port}")
    end
  end
end
