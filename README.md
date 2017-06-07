# Cloud Foundry Redis Service Broker

This repository contains a BOSH release for a Cloud Foundry Redis service
broker.

## Prepare Workspace

Clone the `cf-redis-release` repo into `~/workspace` using:

```
git clone https://github.com/pivotal-cf/cf-redis-release ~/workspace/cf-redis-release
~/workspace/cf-redis-release/scripts/update-release
```

The `routing-release` is a dependent release of `cf-redis-release`, clone it
using:

```
git clone https://github.com/cloudfoundry-incubator/routing-release ~/workspace/routing-release
```

## Deploying

Modify the sample stubs in `templates/sample_stubs` to suit your deployment environment.

Run the `scripts/generate-deployment-manifest` script to generate a deployment manifest. Change the <INFRA> to `aws`, `vsphere` or `warden`.

```
./scripts/generate-deployment-manifest templates/sample_stubs/infrastructure-<INFRA>.yml templates/sample_stubs/meta.yml > manifests/cf-redis-custom.yml
```

Run the `scripts/deploy-release` script. Examples as follows:

```
# Deploying locally to BOSH lite
export BOSH_MANIFEST=manifests/cf-redis-custom.yml
./scripts/deploy-release lite

# Deploying to a different BOSH director
export BOSH_MANIFEST=manifests/cf-redis-custom.yml
./scripts/deploy-release my-bosh-alias
```

Note that the argument is a BOSH alias, which you must have configured prior to running the script. E.G.

```
bosh target https://192.168.50.4:25555 lite
```

## Configuration

### BOSH Lite

You can generate an example bosh-lite deployment manifest as follows:

```
bosh target lite
./scripts/generate-deployment-manifest warden templates/sample_stubs/infrastructure-warden.yml > cf-redis-lite.yml
```
Create an IAM user for the bucket with the following credentials:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1433963499000",
            "Effect": "Allow",
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:DeleteBucketPolicy",
                "s3:DeleteBucketWebsite",
                "s3:DeleteObject",
                "s3:DeleteObjectVersion",
                "s3:GetBucketAcl",
                "s3:GetBucketCORS",
                "s3:GetBucketLocation",
                "s3:GetBucketLogging",
                "s3:GetBucketNotification",
                "s3:GetBucketPolicy",
                "s3:GetBucketRequestPayment",
                "s3:GetBucketTagging",
                "s3:GetBucketVersioning",
                "s3:GetBucketWebsite",
                "s3:GetLifecycleConfiguration",
                "s3:GetObject",
                "s3:GetObjectAcl",
                "s3:GetObjectTorrent",
                "s3:GetObjectVersion",
                "s3:GetObjectVersionAcl",
                "s3:GetObjectVersionTorrent",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads",
                "s3:ListBucketVersions",
                "s3:ListMultipartUploadParts",
                "s3:PutBucketAcl",
                "s3:PutBucketCORS",
                "s3:PutBucketLogging",
                "s3:PutBucketNotification",
                "s3:PutBucketPolicy",
                "s3:PutBucketRequestPayment",
                "s3:PutBucketTagging",
                "s3:PutBucketVersioning",
                "s3:PutBucketWebsite",
                "s3:PutLifecycleConfiguration",
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:PutObjectVersionAcl",
                "s3:RestoreObject"
            ],
            "Resource": [
                "arn:aws:s3:::MYBUCKETNAME/*"
            ]
        }
    ]
}
```

- You can increase the count of the `dedicated-vm` plan nodes from the example of `1`

```
# templates/sample_stubs/sample_warden_stub.yml

properties:
  template_only:
    dedicated_plan:
      instance_count: 1
```
Increase the `instance_count: 1` to the value you want.

### Properties

All required properties are listed in the `templates/sample_stubs/sample_*_stub.yml` files. There are a number of other optional properties. Descriptions for all properties can be found in the relevant `spec` files for each job.

### Broker Registrar
By default, the broker registrar will enable access to your deployed service to
all orgs. You can specify which orgs you wish to grant access to by adding the
following configuration to your manifest:

```
properties:
  redis:
    broker:
      enable_service_access: true
      service_access_orgs:
      - dev_org
      - prod_org
```

### AWS

#### Subnet ACL

Allow the following:
 * Destination port 80 access to the service broker from the cloud controllers
 * Destination port 6379 access to all dedicated nodes from the DEA network(s)
 * Destination ports 32768 to 61000 on the service broker from the DEA network(s). This is only required for the shared service plan.

## Deployment Steps

 1. depending on your IAAS, pick one of the sample Spiff stubs in `templates/sample_stubs/`
 1. adjust the spiff stub based on your environment, i.e. replace all PLACEHOLDERs with actual values (see above details for the Subnet ACL)
 1. target your bosh director, e.g. `bosh target https://192.168.50.4:25555`
 1. create a deployment manifest using the `scripts/generate_deployment_manifest` script, e.g. `./scripts/generate_deployment_manifest warden templates/sample_stubs/sample_warden_stub.yml > cf-redis.yml`
 1. set bosh deployment using the new manifest, i.e. `bosh deployment cf-redis.yml`
 1. upload a cf-redis release, e.g. `bosh upload release releases/cf-redis/cf-redis-[version].yml`
 1. `bosh deploy`
 1. register service broker by runing `bosh run errand broker-registrar`
 1. optionally, run smoke tests to verify your deployment, i.e. `bosh run errand smoke-tests`

## BOSH Links

BOSH supports sharing of information between deployments via
[BOSH Links](https://bosh.io/docs/links.html). This release exposes the redis
`CONFIG` command alias for both dedicated and shared instances. They are
consumed by:

```yaml
consumes:
- name: redis_broker
  type: redis
- name: dedicated_node
  type: redis
```

## Testing

To test first deploy locally using the Bosh-lite instructions above.

### System Tests

To run the system tests locally, just run: `BOSH_MANIFEST=manifests/cf-redis-lite.yml ./scripts/system-tests`.

To run the system tests in docker, just run: `BOSH_MANIFEST=manifests/cf-redis-lite.yml ./scripts/system-tests-in-docker`.

### Unit Tests

The unit tests are run along with the system tests above, you can run them independently also:

To run the unit tests locally, just run: `bundle exec rake spec:unit`.

You can run it from docker by using `./scripts/from-docker bundle exec rake spec:unit`.

## Related Documentation

 * [BOSH](https://bosh.io/docs)
 * [Service Broker API](http://docs.cloudfoundry.org/services/api.html)
 * [Redis](http://redis.io/documentation)
