require 'system_spec_helper'

require 'prof/external_spec/shared_examples/deployment'
require 'prof/external_spec/shared_examples/service_broker'

describe 'logging' do
  let(:log_files_by_job) {
    {
      'cf-redis-broker' => [
        'access.log',
        'cf-redis-broker.stderr.log',
        'cf-redis-broker.stdout.log',
        'error.log',
        'nginx.stderr.log',
        'nginx.stdout.log',
        'process-watcher.stderr.log',
        'process-watcher.stdout.log',
        'route-registrar.stdout.log',
        'route-registrar.stderr.log',
      ]
    }
  }

  it_behaves_like 'a deployment' # log files in /var/vcap/sys/log
  it_behaves_like 'a service broker' # logs to syslog
end
