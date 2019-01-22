require 'yaml'
require 'pry'
require 'open3'

BOSH_CLI = ENV.fetch('BOSH_V2_CLI', 'bosh')

module Helpers
  class Bosh2
    def initialize()
      @bosh_cli = "#{BOSH_CLI} -n"

      version = execute("#{@bosh_cli} --version")
      raise 'BOSH CLI >= v2 required' if version.start_with?('version 1.')
    end

    def execute(command)
      output, = Open3.capture2(command)
      output
    end

    def indexed_instance(instance, index)
      output = execute("#{@bosh_cli} instances | grep #{instance} | cut -f1")
      output.split(' ')[index]
    end

    def deploy(manifest)
      Tempfile.open('manifest.yml') do |manifest_file|
        manifest_file.write(manifest.to_yaml)
        manifest_file.flush
        output = ''
        exit_code = ::Open3.popen3("#{@bosh_cli} deploy #{manifest_file.path}") do |_stdin, stdout, _stderr, wait_thr|
          output << stdout.read
          wait_thr.value
        end
        abort "Deployment failed\n#{output}" unless exit_code == 0
      end
    end

    def start(deployment, instance)
      execute("#{@bosh_cli} -d #{deployment} start #{instance}")
    end

    def stop(deployment, instance)
      execute("#{@bosh_cli} -d #{deployment} stop #{instance}")
    end
  end
end