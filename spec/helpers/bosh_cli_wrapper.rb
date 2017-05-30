require 'open3'
require 'json'
require 'helpers/utilities'

module Helpers
  class BOSHCLIWrapper
    include Utilities

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
      return extract_stdout(stdout)
    end

    def wait_for_process_start(process_name)
      18.times do
        sleep 5
        return true if process_running?(process_name)
      end

      puts "Process #{process_name} did not start within 90 seconds"
      return false
    end

    def wait_for_process_stop(process_name)
      12.times do
        puts "Waiting for #{process_name} to stop"
        sleep 5
        return true if process_not_monitored?(process_name)
      end

      puts "Process #{process_name} did not stop within 60 seconds"
      return false
    end

    def eventually_contains_shutdown_log(prestop_timestamp)
      12.times do
        vm_log = execute("sudo cat /var/log/syslog")
        contains_expected_shutdown_log = drop_log_lines_before(prestop_timestamp, vm_log).any? do |line|
          line.include?('Starting Redis Broker shutdown')
        end

        return true if contains_expected_shutdown_log
        sleep 5
      end

      puts "Broker did not log shutdown within 60 seconds"
      false
    end

    private

    def extract_stdout(raw_output)
      result = JSON.parse(raw_output)
      stdout = []

      blocks = result.fetch('Blocks')
      blocks.each_with_index do |line, index|
        if line.include? 'stdout |'
          stdout << blocks[index+1].strip
        end
      end

      stdout.join("\n")
    end

    def process_running?(process_name)
      monit_output = execute("sudo /var/vcap/bosh/bin/monit summary | grep #{process_name} | grep running")
      !monit_output.strip.empty?
    end

    def process_not_monitored?(process_name)
      monit_output = execute(%Q{sudo /var/vcap/bosh/bin/monit summary | grep #{process_name} | grep "not monitored"})
      !monit_output.strip.empty?
    end
  end
end
