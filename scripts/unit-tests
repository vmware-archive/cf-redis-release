#!/bin/bash

set -e

log() {
  local _message=$1
  echo -e "$_message"
}

bundle install && bundle exec rake spec:unit
