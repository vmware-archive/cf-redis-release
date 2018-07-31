require 'open3'
require 'json'
require 'helpers/utilities'

module Helpers
  module BOSH
    module BaseCommand
      private

      def base_cmd(deployment)
        bosh_cmd = ENV.fetch('BOSH_V2_CLI', 'bosh')
        environment = ENV.fetch('BOSH_ENVIRONMENT')
        ca_cert = ENV.fetch('BOSH_CA_CERT_PATH')
        client = ENV.fetch('BOSH_CLIENT')
        client_secret = ENV.fetch('BOSH_CLIENT_SECRET')

        [
          bosh_cmd,
          "--environment #{environment}",
          "--ca-cert #{ca_cert}",
          "--client #{client}",
          "--client-secret #{client_secret}",
          "--deployment #{deployment}",
          "--json"
        ]
      end
    end

    class Deployment
      include BaseCommand

      def initialize(deployment)
        @deployment = deployment
      end

      def instance(host)
        cmd = base_cmd(@deployment).push("instances").join(' ')

        stdout, stderr, status = Open3.capture3(cmd)

        unless status.success?
          puts stderr
          raise "command failed: #{cmd}"
        end

        result = JSON.parse(stdout)
        table = result.fetch('Tables').first
        rows = table.fetch('Rows')
        match = rows.find { |row| row.fetch('ips') == host }
        return nil if match.nil?

        instance_group, instance_id = match.fetch('instance').split("/")
        return instance_group, instance_id
      end

      def execute(args)
        cmd = base_cmd(@deployment).push(args).join(' ')
        stdout, stderr, status = Open3.capture3(cmd)

        unless status.success?
          puts stderr
          raise "command failed: #{cmd}"
        end

        JSON.parse(stdout)
      end
    end

    class SSH
      include BaseCommand
      include Utilities

      def initialize(deployment_name, instance_group_name, instance_id)
        @deployment = deployment_name
        @instance_group = instance_group_name
        @instance_id = instance_id
        @gw_user = ENV.fetch('JUMPBOX_USERNAME')
        @gw_host = ENV.fetch('JUMPBOX_HOST')
        @gw_private_key = ENV.fetch('JUMPBOX_PRIVATE_KEY_PATH')
      end

      def execute(command)
        cmd = base_cmd(@deployment).concat([
          "ssh",
          "--command '#{command}'",
          "--gw-user #{@gw_user}",
          "--gw-host #{@gw_host}",
          "--gw-private-key #{@gw_private_key}",
          "#{@instance_group}/#{@instance_id}"
        ]).join(' ')

        stdout, _, _ = Open3.capture3(cmd)
        return extract_stdout(stdout)
      end

      def copy(local_path, remote_path)
        cmd = base_cmd(@deployment).concat([
          "scp",
          "--gw-user #{@gw_user}",
          "--gw-host #{@gw_host}",
          "--gw-private-key #{@gw_private_key}",
          local_path,
          "#{@instance_group}/#{@instance_id}:#{remote_path}"
        ]).join(' ')

        stdout, _, process = Open3.capture3(cmd)
        unless process.success?
          raise "SCP command failed, exit status #{process.exitstatus}: #{stdout}"
        end
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
          vm_log = execute("sudo cat /var/vcap/sys/log/cf-redis-broker/cf-redis-broker.stdout.log")
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
            stdout << blocks[index+1].rstrip
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
end
