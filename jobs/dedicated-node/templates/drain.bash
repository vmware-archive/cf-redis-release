#!/bin/bash +e

PIDFILE=/var/vcap/sys/run/redis.pid
LOG_DIR=/var/vcap/sys/log/redis
SHUTDOWN_LOG="${LOG_DIR}"/shutdown_stdout.log
SHUTDOWN_ERR_LOG="${LOG_DIR}"/shutdown_stderr.log

log() {
  echo "$(date): $*" 1>> "$SHUTDOWN_LOG"
}
log_error() {
  echo "$(date): $*" 1>> "$SHUTDOWN_ERR_LOG"
}

if [ ${1} == "kill_quickly" ]; then
    # Try and gracefully give redis 20 seconds to stop, otherwise hard quit
    retry_strategy="TERM/20/QUIT/1/KILL"
else
    # Wait up to 10 minutes for redis to save and shutdown
    retry_strategy="TERM/600"
fi

if [ -f "${PIDFILE}" ]; then
    log "Shutting down redis with shutdown strategy: ${retry_strategy}."

    /sbin/start-stop-daemon \
      --pidfile "$PIDFILE" \
      --retry ${retry_strategy} \
      --oknodo \
      --stop 1>> "$SHUTDOWN_LOG" 2>> "$SHUTDOWN_ERR_LOG"

    exit_status=$?
    case "$exit_status" in
        0)
            log "Shutdown redis successfully."
            ;;
        2)
            log_error "Redis took more than ${retry_strategy} seconds to exit"
            exit 1
            ;;
        *)
            log_error "Failed to exit with start-stop-daemon exit_status: ${exit_status}"
            exit 1
    esac

else
    log "Redis already shutdown"
fi

echo 0
exit 0