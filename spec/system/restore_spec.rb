require 'system_spec_helper'
require 'httparty'

describe 'dedicated-vm restore' do
  let(:service_name)   { bosh_manifest.property('redis.broker.service_name') }
  let(:restore_binary) { '/var/vcap/jobs/redis-backups/bin/restore' }
  let(:backup_dir)     { '/var/vcap/store/redis-backup' }
  let(:local_dump)     { 'spec/fixtures/moaning-dump.rdb' }

  before do
    @service_instance = service_broker.provision_instance(service_name, 'dedicated-vm')
    @service_binding  = service_broker.bind_instance(@service_instance)
    @vm_ip            = @service_binding.credentials[:host]
    @client           = service_client_builder(@service_binding)
    ssh_gateway.scp_to(@vm_ip, local_dump, '/tmp/moaning-dump.rdb')
    root_execute_on(@vm_ip, "mv /tmp/moaning-dump.rdb #{backup_dir}/dump.rdb")
    expect(@client.read("moaning")).to_not eq("myrtle")
    root_execute_on(@vm_ip, "#{restore_binary} -sourceRDB #{backup_dir}/dump.rdb")
  end

  after do
    service_broker.unbind_instance(@service_binding)
    service_broker.deprovision_instance(@service_instance)
  end

  it 'restores data to a dedicated-vm instance' do
    expect(@client.read("moaning")).to eq("myrtle")
  end

  it 'logs successful completion of restore' do

    output = root_execute_on(@vm_ip, "cat /var/vcap/sys/log/redis-backups/redis-backups.log")

    expect(output).to include('"restore.LogRestoreComplete","log_level":1,"data":{"message":"Redis data restore completed successfully"}}')
  end
end

describe 'shared-vm restore' do
  let(:service_name)   { bosh_manifest.property('redis.broker.service_name') }
  let(:restore_binary) { '/var/vcap/jobs/redis-backups/bin/restore' }
  let(:backup_dir)     { '/var/vcap/store/redis-backup' }
  let(:local_dump)     { 'spec/fixtures/moaning-dump.rdb' }

  before do
    @service_instance = service_broker.provision_instance(service_name, 'shared-vm')
    @service_binding  = service_broker.bind_instance(@service_instance)
    @vm_ip            = @service_binding.credentials[:host]
    @client           = service_client_builder(@service_binding)
    ssh_gateway.scp_to(@vm_ip, local_dump, '/tmp/moaning-dump.rdb')
    root_execute_on(@vm_ip, "mv /tmp/moaning-dump.rdb #{backup_dir}/dump.rdb")
    expect(@client.read("moaning")).to_not eq("myrtle")
    redisConfDir = "/var/vcap/store/cf-redis-broker/redis-data/#{@service_instance.id}"
    redisDbDir = "/var/vcap/store/cf-redis-broker/redis-data/#{@service_instance.id}/db"

    root_execute_on(@vm_ip, "#{restore_binary} -redisConfDir #{redisConfDir} -redisDbDir #{redisDbDir} -sourceRDB #{backup_dir}/dump.rdb")
  end

  after do
    # temporary fix, see #135523595
    expect(broker_registered?).to be true

    service_broker.unbind_instance(@service_binding)
    service_broker.deprovision_instance(@service_instance)
  end

  it 'restores data to a shared-vm instance' do
    expect(@client.read("moaning")).to eq("myrtle")
  end

  it 'logs successful completion of restore' do

    output = root_execute_on(@vm_ip, "cat /var/vcap/sys/log/redis-backups/redis-backups.log")

    expect(output).to include('"restore.LogRestoreComplete","log_level":1,"data":{"message":"Redis data restore completed successfully"}}')
  end
end

def broker_registered?
  uri = URI.parse('https://' + bosh_manifest.property('broker.host') + '/v2/catalog')

  auth = {
    username: bosh_manifest.property("broker.username"),
    password: bosh_manifest.property("broker.password")
  }

  15.times do |n|
    puts "Checking if broker is responding, Attempt: #{n}"
    response = HTTParty.get(uri, verify: false, basic_auth: auth)

    if response.code == 200
      return true
    end

    sleep 1
  end

  false
end
