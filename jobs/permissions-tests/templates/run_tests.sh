#!/bin/bash

set -e

source /var/vcap/packages/golang-1.9-linux/bosh/runtime.env
export GOPATH=$GOPATH:/var/vcap/packages/permissions-tests

cd /var/vcap/packages/permissions-tests/src/permissions-tests

/var/vcap/packages/ginkgo/ginkgo -r -v -noColor=true -keepGoing=true -trace=true -slowSpecThreshold=300
