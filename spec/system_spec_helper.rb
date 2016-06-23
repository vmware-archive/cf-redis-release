require 'yaml'
require 'helpers/environment'
require 'prof/external_spec/spec_helper'
require 'prof/matchers/only_support_ssl_with_cipher_set'
require 'aws-sdk'

ROOT = File.expand_path('..', __dir__)

module Helpers
  module Environment
    def cf_api
      ENV['CF_API'] || 'https://api.bosh-lite.com'
    end

    def cf_username
      ENV['CF_USERNAME'] || "admin"
    end

    def cf_password
      ENV['CF_PASSWORD'] || "admin"
    end

    def doppler_address
      ENV['DOPPLER_ADDR'] || "wss://doppler.bosh-lite.com:4443"
    end

    def target_cf
      `cf api --skip-ssl-validation #{cf_api}`
    end

    def cf_login
      `cf auth #{cf_username} #{cf_password}`
    end

    def cf_auth_token
      target_cf
      cf_login
      `cf oauth-token | tail -n 1`.strip!
    end
  end
end

module ExcludeHelper
  def self.manifest
    @bosh_manifest ||= YAML.load(File.read(ENV['BOSH_MANIFEST']))
  end

  def self.metrics_available?
    0 != manifest.fetch('releases').select{|i| i["name"] == "service-metrics" }.length
  end

  def self.run_backup_spec?
    manifest
      .fetch('properties')
      .fetch('redis')
      .fetch('broker').has_key?('backups')
  end

  def self.service_backups_available?
    0 != manifest.fetch('releases').select{|i| i["name"] == "service-backup"}.length
  end

  def self.warnings
    message = "\n"
    if !metrics_available?
      message += "INFO: Skipping metrics tests, metrics are not available in this manifest\n"
    end

    if !service_backups_available?
      message += "INFO: Skipping service backups tests, service backups are not available in this manifest\n"
    end

    message + "\n"
  end
end

puts ExcludeHelper::warnings

RSpec.configure do |config|
  config.include Helpers::Environment
  config.include Prof::Matchers
  config.filter_run :focus
  config.run_all_when_everything_filtered = true
  config.order = 'random'
  config.full_backtrace = true
  config.filter_run_excluding :skip_metrics => !ExcludeHelper::metrics_available?
  config.filter_run_excluding :skip_service_backups => !ExcludeHelper::service_backups_available?
  config.filter_run_excluding :skip_backups => ExcludeHelper::service_backups_available? && !ExcludeHelper::run_backup_spec?

  config.before(:all) do
    redis_service_broker.deprovision_service_instances!

    if ExcludeHelper::service_backups_available?
      Aws.config.update({
        region: 'us-east-1',
        credentials: Aws::Credentials.new(
          bosh_manifest.property('service-backup.destination.s3.access_key_id'),
          bosh_manifest.property('service-backup.destination.s3.secret_access_key')
        )
      })
    elsif ExcludeHelper::run_backup_spec?
      Aws.config.update({
        region: 'us-east-1',
        credentials: Aws::Credentials.new(
          bosh_manifest.property('redis.broker.backups.access_key_id'),
          bosh_manifest.property('redis.broker.backups.secret_access_key')
        )
      })
    end
  end
end
