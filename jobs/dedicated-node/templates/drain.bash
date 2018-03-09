#!/bin/bash +e

PIDFILE=/var/vcap/sys/run/redis.pid
LOG_DIR=/var/vcap/sys/log/redis
SHUTDOWN_LOG="${LOG_DIR}"/shutdown_stdout.log
SHUTDOWN_ERR_LOG="${LOG_DIR}"/shutdown_stderr.log
REDIS_CLI_COMMAND=/var/vcap/packages/redis/bin/redis-cli
REDIS_PASS="$(awk '$1 == "requirepass" {print $2}' /var/vcap/store/redis/redis.conf)"
REDIS_PORT=$(awk '$1 == "port" {print $2}' /var/vcap/store/redis/redis.conf)

log() {
  echo "$(date): $*" 1>> "$SHUTDOWN_LOG"
}
log_error() {
  echo "$(date): $*" 1>> "$SHUTDOWN_ERR_LOG"
}

if [ -f "${PIDFILE}" ]; then

    if [ ${1} == "quickly" ]; then
        log "Will try and gracefully shutdown redis for 25"
        retry_strategy="TERM/25"
    else
        log "Will try and gracefully shutdown redis for 10 minutes and fail if redis fails to save and quit in that time"
        retry_strategy="TERM/600"
    fi

    ${REDIS_CLI_COMMAND} -p ${REDIS_PORT} -a "${REDIS_PASS}" BGREWRITEAOF

    timeout_timestamp=$(($(date "+%s") + 120))
    until ${REDIS_CLI_COMMAND} -p ${REDIS_PORT} -a "${REDIS_PASS}" INFO | grep aof_rewrite_in_progress:0
    do
      if [ $timeout_timestamp -lt $(date "+%s") ]; then
        log_error "Redis failed to rewrite AOF file within 120 seconds"
        exit 1
      fi

      sleep 1
    done

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
