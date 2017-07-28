# Cloud Foundry Redis Service Broker

This repository contains a BOSH release for a Cloud Foundry Redis service
broker.

```shell
git clone https://github.com/pivotal-cf/cf-redis-release ~/workspace/cf-redis-release
cd ~/workspace/cf-redis-release
git submodule update --init --recursive
```

## Deployment dependencies

1. bosh2 CLI (you may use the old CLI but instructions will use the new one)
1. `direnv` (or set envs yourself)
1. a bosh director
1. a cloud foundry deployment
1. fill out the following envs of the `.envrc.template` file and save as .envrc:
   - BOSH_ENVIRONMENT
   - BOSH_CA_CERT
   - BOSH_CLIENT
   - BOSH_CLIENT_SECRET
   - BOSH_DEPLOYMENT
1. `direnv allow`
1. routing release `0.157.0` (`bosh upload-release http://bosh.io/d/github.com/cloudfoundry-incubator/cf-routing-release?v=0.157.0`)
1. syslog-migration release `7` (`bosh upload-release https://github.com/pivotal-cf/syslog-migration-release/releases/download/v7/syslog-migration-7.tgz`)

## Deployment

Populate a vars file (using `manifest/vars-lite.yml` as a template), save it to
`secrets/vars.yml`. You will need values from both your cloud-config and secrets
from your cf-deployment.

To deploy:

```shell
bosh upload-stemcell https://s3.amazonaws.com/bosh-core-stemcells/warden/bosh-stemcell-3363.27-warden-boshlite-ubuntu-trusty-go_agent.tgz
bosh create-release
bosh upload-release
bosh deploy --vars-file secrets/vars.yml manifest/deployment.yml
```

## Network Configuration

The following ports and ranges are used in this service:

- broker vm, port 12350: access to the broker from the cloud controllers
- broker vm, ports 32768-61000: on the service broker from the Diego Cell and
Diego Brain network(s). This is only required for the shared service plan
- dedicated node, port 6379: access to all dedicated nodes from the Diego Cell
and Diego Brain network(s)

## Testing

1. `bundle install`
1. `bundle exec rspec spec`

## Related Documentation

 * [BOSH](https://bosh.io/docs)
 * [Service Broker API](http://docs.cloudfoundry.org/services/api.html)
 * [Redis](http://redis.io/documentation)
