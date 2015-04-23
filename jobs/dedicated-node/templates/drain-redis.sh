#!/bin/sh

set -e

RUN_DIR=/var/vcap/sys/run
PIDFILE=$RUN_DIR/redis.pid

if [ -f "$PIDFILE" ]; then
  pid=$(head -1 "$PIDFILE")
  kill $pid
  echo "-5"
else
  echo "0"
fi
