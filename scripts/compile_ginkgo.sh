#!/usr/bin/env bash

set -eu

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$DIR" )"

GOPATH="$( mktemp -d )"
mkdir "${GOPATH}/src"
cp -R "${PROJECT_DIR}/src/cf-redis-smoke-tests/vendor/" "${GOPATH}/src/"

go_version="$(go version)"
ginkgo_sha="$(cat "${PROJECT_DIR}/src/cf-redis-smoke-tests/vendor/manifest" | jq --raw-output '.dependencies | map(select(.importpath == "github.com/onsi/ginkgo")) | .[0].revision')"

pushd "$GOPATH"
  GOOS=linux GOARCH=amd64 go build github.com/onsi/ginkgo/ginkgo
popd

cp "${GOPATH}/ginkgo" "${PROJECT_DIR}/"
rm -rf "$GOPATH"

echo "compiled ginkgo successfully for linux amd64"
echo "$go_version"
echo "ginkgo git sha: ${ginkgo_sha}"
