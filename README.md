# Cloud Foundry Redis Release

This repository contains a BOSH release for a Cloud Foundry Redis service
broker. It supports shared-vm plans. Dedicated-vm plans are being deprecated.

> There is no active feature development for this repository. Please note that
some features *might* change or get removed in future commits.

```shell
git clone https://github.com/pivotal-cf/cf-redis-release ~/workspace/cf-redis-release
cd ~/workspace/cf-redis-release
git submodule update --init --recursive
```

## Deployment dependencies

1. [BOSH CLI v2+](https://github.com/cloudfoundry/bosh-cli) (you may use the old [BOSH CLI](https://github.com/cloudfoundry/bosh) but instructions will use the new one)
2. [direnv](https://github.com/direnv/direnv) (or set environment variables yourself)
3. a bosh director
4. a cloud foundry deployment

## Deployment
Source bosh-lite lock file from `london-services-locks/redis-bosh-lite-pool/ready/claimed/`.
If this is a fresh bosh-lite you may need to upload the (warden) stemcell specified at the top of `scripts/deploy_to_bosh_lite`.

Run `./scripts/deploy_to_bosh_lite`, if the bosh v2 cli is something other than `bosh` then specify it with, e.g. `BOSH_CLI=bosh2`.
This will generate a `.envrc` file that will then allow you to run system tests against the deployment with `bundle exec rake spec:system`.

## Network Configuration

The following ports and ranges are used in this service:

- broker vm, port 12350: access to the broker from the cloud controllers
- broker vm, ports 32768-61000: on the service broker from the Diego Cell and
Diego Brain network(s). This is only required for the shared service plan
- dedicated node, port 6379: access to all dedicated nodes from the Diego
Cell and Diego Brain network(s)

## Testing

1. install gem requirements 
    ```shell
    bundle install
    ```
2. run the tests
    ```
    bundle exec rspec spec`
    ```

## Related Documentation

 * [BOSH](https://bosh.io/docs)
 * [Service Broker API](http://docs.cloudfoundry.org/services/api.html)
 * [Redis](http://redis.io/documentation)

## Known Issues
### Possible Data Leak when disabling Static IPs
In the past cf-redis-release expected to be deployed [with static
IPs](https://github.com/pivotal-cf/cf-redis-release/blob/23a218a06188ba9dd5694698bfa9fd4b5131b707/manifest/deployment.yml#L54)
for dedicated nodes specified in the manifest. It is often more desired to deploy
without static IPs leaving BOSH to manage IP allocation.

There is a risk of data leak when transitioning from static to dynamic IPs.
Consider the following scenario:

The operator:

1. has deployed cf-redis-release with static IPs
1. now decides to use dynamic IP allocation, and removes the static IPs from
   the manifest
1. then DOES NOT remove the static IPs from [cloud config](https://bosh.io/docs/networks/)
1. re-deploys cf-redis-release with the new manifest

In the previous scenario BOSH will dynamically allocate IPs to the dedicated
instances. BOSH will not try to re-use the previous IPs since those are still
restricted in the cloud config. Since the IPs have changed, application
bindings will break and the state in the broker will be out of sync with the
new deployment. It is possible that previously allocated instances containing
application data are erroneously re-allocated to another unrelated
application, causing data to be leaked.

In order to avoid this scenario, the operator must remove the reserved static
IPs in the cloud config at the same time as they are remove from the
manifest. This will allow BOSH to keep the same IP addresses for the existing
nodes.

To safely transition from static to dynamic IPs:
1. look up the static IPs that were specified in the manifest when deploying
your dedicated nodes
1. ensure these IPs are no longer included in the static range of the network
in your cloud config
1. remove the static IPs from the manifest
1. deploy using the manifest without static IPs
