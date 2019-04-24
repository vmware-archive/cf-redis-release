require 'yaml'
require 'helpers/environment'
require 'helpers/utilities'
require 'rspec_junit_formatter'
require 'aws-sdk'

ROOT = File.expand_path('..', __dir__)

def test_manifest
  @test_manifest ||= YAML.load_file(ENV.fetch('BOSH_MANIFEST'))
end

def deployment_name
  test_manifest.fetch('name')
end

module Helpers
  module Environment
    def cf_api
      ENV['CF_API'] || 'https://api.bosh-lite.com'
    end

    def cf_username
      ENV['CF_USERNAME'] || 'admin'
    end

    def cf_password
      ENV['CF_PASSWORD'] || 'admin'
    end

    def cf_target
      `cf api --skip-ssl-validation #{cf_api}`
    end

    def cf_login
      `cf auth #{cf_username} #{cf_password}`
    end

    def cf_auth_token
      cf_target
      cf_login
      `cf oauth-token | tail -n 1`.strip!
    end
  end
end

module ExcludeHelper
  def self.metrics_available?
    !test_manifest.fetch('releases').select { |i| i['name'] == 'service-metrics' }.empty?
  end

  def self.service_backups_available?
    !test_manifest.fetch('releases').select { |i| i['name'] == 'service-backup' }.empty?
  end

  def self.warnings
    message = "\n"
    unless metrics_available?
      message += "INFO: Skipping metrics tests, metrics are not available in this manifest\n"
    end

    unless service_backups_available?
      message += "INFO: Skipping service backups tests, service backups are not available in this manifest\n"
    end

    message + "\n"
  end
end

puts ExcludeHelper.warnings

RSpec.configure do |config|
  config.include Helpers::Environment
  config.include Helpers::Utilities
  config.filter_run :focus
  config.run_all_when_everything_filtered = true
  config.order = 'random'
  config.full_backtrace = true
  config.filter_run_excluding skip_metrics: !ExcludeHelper.metrics_available?
  config.filter_run_excluding skip_service_backups: !ExcludeHelper.service_backups_available?

  config.formatter = :documentation
  config.add_formatter RSpecJUnitFormatter, 'rspec.xml'
  config.full_backtrace = true


  config.before(:all) do
    redis_service_broker.deprovision_dedicated_service_instances!
    redis_service_broker.deprovision_shared_service_instances!

    if ExcludeHelper.service_backups_available?
      destinations = test_manifest['properties']['service-backup']['destinations']
      aws_access_key_id = destinations[0]['config']['access_key_id']
      secret_access_key = destinations[0]['config']['secret_access_key']
      Aws.config.update(
        region: 'us-east-1',
        credentials: Aws::Credentials.new(
          aws_access_key_id,
          secret_access_key
        )
      )
    end
  end
end
