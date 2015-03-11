# Cloud Foundry Redis Service Broker

This repository contains a BOSH release for a Cloud Foundry Redis service
broker.

## Getting Started

Clone the repository using `git clone --recursive`.

### git-hooks

The `githooks` directory includes hooks that will only run if
[git-hooks](http://git-hooks.github.io/git-hooks) has been initialized for this
repository on this machine. Sprout-wrap does this by default on CF London
machines. If you are on a different machine, please run `git hooks install` in
the root dir of this repository.

## Properties

Example manifests for BOSH Lite and AWS are provided in `/manifests`. All
required properties are shown in these examples. There are a number of other
optional properties. Descriptions for all properties can be found in the
relevant `spec` files for each job.

## Related Documentation

 * [BOSH](https://bosh.io/docs)
 * [Service Broker API](http://docs.cloudfoundry.org/services/api.html)
 * [Redis](http://redis.io/documentation)
