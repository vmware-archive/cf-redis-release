require 'yaml'
require 'pry'
require 'open3'

BOSH_CLI = ENV.fetch('BOSH_V2_CLI', 'bosh')
MANIFEST_PATH = ENV.fetch('BOSH_MANIFEST')

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

    def deploy(deployment, manifest = MANIFEST_PATH)
      execute("#{@bosh_cli} -d #{deployment} deploy #{manifest}")
    end

    def recreate(deployment, instance)
      execute("#{@bosh_cli} -d #{deployment} recreate #{instance} --force")
    end

    def start(deployment, instance)
      execute("#{@bosh_cli} -d #{deployment} start #{instance}")
    end

    def stop(deployment, instance)
      execute("#{@bosh_cli} -d #{deployment} stop #{instance}")
    end
  end
end