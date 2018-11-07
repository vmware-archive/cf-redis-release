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
Run the following steps:

1. fill out the following environment variables of the `.envrc.template` file
and save as .envrc or export them. All or almost all the variables are required for tests but these are the minimum required for deploy:
   - BOSH_ENVIRONMENT
   - BOSH_CA_CERT
   - BOSH_CLIENT
   - BOSH_CLIENT_SECRET
   - BOSH_DEPLOYMENT
1. if you're using the `.envrc` file
    ```shell
    direnv allow
    ```
1. upload dependent releases
    ```shell
    bosh upload-release http://bosh.io/d/github.com/cloudfoundry-incubator/cf-routing-release
    bosh upload-release http://bosh.io/d/github.com/cloudfoundry/syslog-release
    bosh upload-release http://bosh.io/d/github.com/cloudfoundry-incubator/bpm-release # required for routing 180+
    ```

Populate a vars file (using `manifest/vars-lite.yml` as a template), save it
to `secrets/vars.yml`. You will need values from both your cloud-config and
secrets from your cf-deployment.

To deploy:

```shell
bosh upload-stemcell https://s3.amazonaws.com/bosh-core-stemcells/warden/bosh-stemcell-97.3-warden-boshlite-ubuntu-xenial-go_agent.tgz
bosh create-release
bosh upload-release
bosh deploy --vars-file secrets/vars.yml manifest/deployment.yml
```

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
    bundle exec rspec spec
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

## Errands

The Cf-Redis Service Broker offers the following [BOSH errands](https://bosh.io/docs/errands/):

### broker-registrar
Communicates to the CloudFoundry [Cloud Controller](https://docs.cloudfoundry.org/concepts/architecture/cloud-controller.html)
which maintains the database for the [CF Marketplace](https://cli.cloudfoundry.org/en-US/cf/marketplace.html).
This enables the service plans on the CF Marketplace so that App Developers can create and delete service instances of those plans.

**Note:** As of v434.0.13, the broker-registrar will disable service access to the dedicated-vm service plan
as the service plan is being deprecated.

### broker-deregistrar
Communicates with the CF Cloud Controller to remove the cf-redis broker and service plans from the CF Marketplace
as well as [delete the broker deployment](https://cli.cloudfoundry.org/en-US/cf/delete-service-broker.html) from BOSH.

**Note:** If any service instances exist, the errand will **fail**. This is to prevent orphan deployments which the CF Cloud Controller will lose record of but will continue to live as a BOSH deployment which would continue to incur costs.

If you wish to remove the service broker, perform a
`cf delete-service SERVICE_INSTANCE` and remove all service instances associated with the broker and run the errand after all service instances have been removed.

### smoke-tests
Runs smoke tests which tests the lifecycle and functionality of the both the dedicated-vm and shared-vm services.
See the [Redis documentation](https://docs.pivotal.io/redis/smoke-tests.html) for more information.

### remove-deprecated-functionality
Available as of v434.0.13. Communicates with the CF Cloud Controller to disable service access to the dedicated-vm service plan.
This allows operators to remove the dedicated-vm service plan from the marketplace
in order to prevent App Developers from creating new service instances in preparation for the deprecation of the dedicated-vm plan.

### cleanup-metadata-if-dedicated-disabled
Available as of v434.0.15. Communicates with the CF Cloud Controller to purge references to dedicated-vm service instances
if no dedicated-vms have been provisioned. The purpose for this errand is to provide a smoother experience for migrating
to On-Demand Instances given the Ops Manager tile deployment flow. Intended as a temporary errand during deprecation of dedicated-vms.
