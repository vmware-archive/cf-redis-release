#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$DIR" )"

pushd "$PROJECT_DIR"
  echo "Running bosh release unit tests"
  bundle install && bundle exec rake spec:unit
popd

echo "Running cf-redis-broker unit tests"

mkdir -p "${GOPATH}/src/github.com/pivotal-cf"
cp -r "${PROJECT_DIR}/src/cf-redis-broker" "${GOPATH}/src/github.com/pivotal-cf/"

"${GOPATH}/src/github.com/pivotal-cf/cf-redis-broker/script/test-ci"

rm -rf "${GOPATH}/src/github.com/pivotal-cf/cf-redis-broker/"
