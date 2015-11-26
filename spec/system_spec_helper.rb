require 'helpers/environment'
require 'prof/external_spec/spec_helper'
require 'prof/matchers/only_support_ssl_with_cipher_set'

ROOT = File.expand_path('..', __dir__)

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
