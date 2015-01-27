#!/bin/bash

set -e

log_dir=/var/vcap/sys/log/cf-redis-broker

disable_process_watcher() {
    echo "`date +%c` - Disabling process watcher" >> ${log_dir}/drain.log 2>&1

    process_watcher_pidfile="/var/vcap/sys/run/cf-redis-broker/process-watcher.pid"

    if [ -f $process_watcher_pidfile ]
    then
      process_watcher_pid=`cat $process_watcher_pidfile`
      set +e
        kill -USR1 $process_watcher_pid
      set -e
    fi

    sleep 1
}

echo "`date +%c` - Starting drain" >> ${log_dir}/drain.log 2>&1

disable_process_watcher

#pkill returns 1 when no instances of process to kill are running
set +e
  /usr/bin/pkill redis-server
set -e

if /bin/pidof redis-server > /dev/null 2>&1
then
  echo "`date +%c` - Waiting for redis-server shutdown" >> ${log_dir}/drain.log 2>&1
  echo -10
else
  echo "`date +%c` - All redis-servers shutdown" >> ${log_dir}/drain.log 2>&1
  echo 0
fi

exit 0
