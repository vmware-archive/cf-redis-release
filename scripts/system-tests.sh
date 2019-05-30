#!/bin/bash

set -e

log() {
  local _message=$1
  echo -e "$_message"
}

check_args() {
  if [ -z "$BOSH_MANIFEST" ]
  then
    log "Please set the BOSH_MANIFEST environment variable to the path to your manifest file"
    log "E.G. export BOSH_MANIFEST=/home/example/cf-redis-release/manifests/bosh-lite.yml"
    exit 1
  fi
}

export_bosh_ca_cert_path() {
  if [ -n "$BOSH_CA_CERT" ]
  then
    local path; path="$(mktemp -d)/bosh.crt"
    echo -e "$BOSH_CA_CERT" > "$path"
    chmod 400 "$path"
    export BOSH_CA_CERT_PATH=$path
  fi
}

export_jumpbox_private_key_path() {
  if [ -n "$JUMPBOX_PRIVATE_KEY" ]
  then
    local jumpbox_key_path; jumpbox_key_path="$(mktemp -d)/jumpbox.pem"
    echo -e "$JUMPBOX_PRIVATE_KEY" > "$jumpbox_key_path"
    chmod 400 "$jumpbox_key_path"
    export JUMPBOX_PRIVATE_KEY_PATH=$jumpbox_key_path
  fi
}

check_args
export_bosh_ca_cert_path
export_jumpbox_private_key_path

bundle install && bundle exec rake spec:system
