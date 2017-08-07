require 'system_spec_helper'
require 'aws-sdk'

describe 'process-watcher startup logging' do
  let(:processWatcherPath) { '/var/vcap/sys/log/monit/process-watcher_ctl.err.log' }

  before do
    monitRestartProcessWatcherAndClearLogs()
  end

  it 'does not log that another processmonitor process is running' do
    log_output = root_execute_on(broker_host, "cat #{processWatcherPath}")
    expect(log_output).not_to include "processmonitor already running"
  end

  context 'when a processmonitor process already exists' do
    before do
      startFakeProcessMonitor()
      monitRestartProcessWatcherAndClearLogs()
    end

    after do
      stopFakeProcessMonitor()
      monitRestartProcessWatcherAndClearLogs()
    end

    it 'logs that another processmonitor process is running' do
      log_output = root_execute_on(broker_host, "cat #{processWatcherPath}")
      expect(log_output).to include 'processmonitor already running'
    end
  end
end

def monitRestartProcessWatcherAndClearLogs()
  root_execute_on(broker_host, "truncate -s 0 #{processWatcherPath}")
  root_execute_on(broker_host, '/var/vcap/bosh/bin/monit restart process-watcher')
  expect(wait_for_process_start('process-watcher', broker_host)).to eq(true)
end

def startFakeProcessMonitor()
  @t = Thread.new{
    ssh_gateway.execute_on(broker_host, 'bash -c "exec -a fakeprocessmonitor sleep 10000"')
  }
end

def stopFakeProcessMonitor()
  ssh_gateway.execute_on(broker_host, 'kill `pidof fakeprocessmonitor`')
  @t.kill
end
