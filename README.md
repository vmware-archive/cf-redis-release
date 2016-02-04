# Cloud Foundry Redis Service Broker

This repository contains a BOSH release for a Cloud Foundry Redis service
broker.

## Updating

Clone the repository and run `./scripts/update-release`.

## Deploying

Run the `scripts/deploy-release` script. Examples as follows:

```
# Deploying locally to BOSH lite
./scripts/deploy-release manifests/cf-redis-lite.yml lite

# Deploying to a different BOSH director
./scripts/deploy-release manifests/my-custom-redis.yml my-bosh-alias
```

Note that the second argument is a BOSH alias, which you must have configured prior to running the script. E.G.

```
bosh target https://192.168.50.4:25555 lite
```

## Testing

### Unit Tests

To run the unit tests locally, just run: `bundle exec rake spec:unit`.

You can run it from docker by using `./scripts/from-docker bundle exec rake spec:unit`.

### BOSH Lite
An example manifest for BOSH Lite is provided in `/manifests/cf-redis-lite.yml`

To use this manifest:

1. Update the director guid

```
---
name: cf-redis
director_uuid: REPLACE_WITH_DIRECTOR_ID
```

2. You can increase the count of the `dedicated-vm` plan nodes from the example of `1`

**Note:** If your bosh-lite does not have enough capacity to handle the increased nodes resource requirements, your deployment will likely fail.

```
jobs:
- name: dedicated-node
  templates:
  - name: dedicated-node
    release: cf-redis
  - name: syslog-configurator
    release: cf-redis
  instances: 1
  resource_pool: services-small
  persistent_disk: 4096
  networks:
  - name: services
    static_ips:
    - 10.244.3.54
```
Increase the `instances: 1` to the value you want.
Add an additional static ip to `static_ips:` for every node

You must also add these additional IPs in the properties block at the end of the manifest

```
  redis:
    maxmemory: 262144000
    config_command: config
    save_command: save
    bg_save_command: bgsave
    broker:
      network: services
      dedicated_nodes:
      - 10.244.3.54
```

3. If you want to enable the backup functionality, populate these fields in the properties block at the end of the manifest

```
      backups:
        path:
        access_key_id:
        secret_access_key:
        endpoint_url:
        bucket_name:
```

If these values are not populated, the scheduled backups will not run.


### Properties

Example manifests for BOSH Lite and AWS are provided in `/manifests`. All
required properties are shown in these examples. There are a number of other
optional properties. Descriptions for all properties can be found in the
relevant `spec` files for each job.

## Deploying

### Subnet ACL

Allow the following: 
 * Destination port 80 access to the service broker from the cloud controllers
 * Destination port 6379 access to all dedicated nodes from the DEA network(s)
 * Destination ports 32768 to 61000 on the service broker from the DEA network(s). This is only required for the shared service plan.

### Deployment Steps

 1. depending on your IAAS, pick one of the sample Spiff stubs in `templates/sample_stubs/`
 1. adjust the spiff stub based on your environment, i.e. replace all PLACEHOLDERs with actual values (see above details for the Subnet ACL)
 1. create a deployment manifest using spiff, e.g. `spiff merge cf-redis-deployment.yml cf-infrastructure-aws.yml sample_stubs/sample_aws_stub.yml > cf-redis.yml`
 1. set bosh deployment using the new manifest, i.e. `bosh deployment cf-redis.yml`
 1. upload a cf-redis release, e.g. `bosh upload release releases/cf-redis/cf-redis-384.yml`
 1. `bosh deploy`
 1. register service broker by runing `bosh run errand broker-registrar`
 1. optionally, run smoke tests to verify your deployment, i.e. `bosh run errand smoke-tests`

## Related Documentation

 * [BOSH](https://bosh.io/docs)
 * [Service Broker API](http://docs.cloudfoundry.org/services/api.html)
 * [Redis](http://redis.io/documentation)
