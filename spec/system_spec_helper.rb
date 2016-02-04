require 'helpers/environment'
require 'prof/external_spec/spec_helper'
require 'prof/matchers/only_support_ssl_with_cipher_set'

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
      ENV['DOPPLER_ADDR'] || "wss://doppler.bosh-lite.com:443"
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

RSpec.configure do |config|
  config.include Helpers::Environment
  config.include Prof::Matchers
  config.filter_run :focus
  config.run_all_when_everything_filtered = true
  config.order = 'random'
  config.full_backtrace = true

  config.before(:all) do
    redis_service_broker.deprovision_service_instances!
  end
end
