require 'system_spec_helper'
require 'aws-sdk'

PROCESS_WATCHER_PATH = '/var/vcap/sys/log/monit/process-watcher_ctl.err.log'

describe 'process-watcher startup logging' do
  it 'does not log that another processmonitor process is running' do
    clear_log_and_restart_process_watcher
    log_output = broker_ssh.execute("sudo cat #{PROCESS_WATCHER_PATH}")
    expect(log_output).not_to include "processmonitor already running"
  end

  context 'when a processmonitor process already exists' do
    it 'logs that another processmonitor process is running' do
      fake_thread = start_fake_process_monitor
      clear_log_and_restart_process_watcher

      log_output = broker_ssh.execute("sudo cat #{PROCESS_WATCHER_PATH}")
      expect(log_output).to include 'processmonitor already running'

      stop_fake_process_monitor(fake_thread)
      clear_log_and_restart_process_watcher
    end
  end
end

def clear_log_and_restart_process_watcher
  clear_process_watcher_logs
  broker_ssh.execute('sudo /var/vcap/bosh/bin/monit restart process-watcher')
  expect(broker_ssh.wait_for_process_start('process-watcher')).to eq(true)
end

def clear_process_watcher_logs
  broker_ssh.execute("sudo truncate -s 0 #{PROCESS_WATCHER_PATH}")
end

def start_fake_process_monitor
  Thread.new do
    broker_ssh.execute('bash -c "exec -a fakeprocessmonitor sleep 10000"')
  end
end

def stop_fake_process_monitor(fake_thread)
  broker_ssh.execute('sudo kill `pidof fakeprocessmonitor`')
  fake_thread.kill
end
