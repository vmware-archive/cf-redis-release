require 'open3'
require 'json'

module Helpers
  module SSHTargets
    include Environment

    def broker_ssh
      BOSHCLIWrapper.new(bosh_manifest.deployment_name, BROKER_JOB_NAME)
    end
  end

  class BOSHCLIWrapper
    def initialize(deployment_name, instance_group_name)
      @environment = ENV.fetch('BOSH_TARGET')
      @ca_cert = ENV.fetch('BOSH_CA_CERT')
      @client = ENV.fetch('BOSH_CLIENT')
      @client_secret = ENV.fetch('BOSH_CLIENT_SECRET')
      @deployment = deployment_name
      @gw_user = ENV.fetch('JUMPBOX_USERNAME')
      @gw_host = ENV.fetch('JUMPBOX_HOST')
      @gw_private_key = ENV.fetch('JUMPBOX_PRIVATE_KEY')
      @instance_group = instance_group_name
    end

    def execute(command)
      cmd = [
        "bosh-go-cli",
        "--environment #{@environment}",
        "--ca-cert #{@ca_cert}",
        "--client #{@client}",
        "--client-secret #{@client_secret}",
        "--deployment #{@deployment}",
        "--json",
        "ssh",
        "--command '#{command}'",
        "--gw-user #{@gw_user}",
        "--gw-host #{@gw_host}",
        "--gw-private-key #{@gw_private_key}",
        "#{@instance_group}/0"
      ].join(' ')

      stdout, _, _ = Open3.capture3(cmd)
      extract_stdout(stdout)
    end

    private

    def extract_stdout(raw_output)
      result = JSON.parse(raw_output)
      stdout = []

      result.fetch('Blocks').each_slice(3) do |slice|
        stdout << slice[1].strip if slice[0].include? 'stdout |'
      end

      stdout.join("\n")
    end
  end
end
