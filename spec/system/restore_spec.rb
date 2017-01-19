require 'system_spec_helper'
require 'httparty'

RESTORE_BINARY = '/var/vcap/jobs/redis-backups/bin/restore'
BACKUP_PATH = '/var/vcap/store/dump.rdb'

shared_examples 'it can restore Redis' do |plan|
  before(:all) do
    @service_instance, @service_binding, @vm_ip, @client = provision_and_build_service_client plan
    preprovision_timestamp = root_execute_on(@vm_ip, "date +%s")
    stage_dump_file @vm_ip
    expect(@client.read("moaning")).to_not eq("myrtle")

    execute_restore_as_root (get_restore_args plan, @service_instance.id, BACKUP_PATH), @vm_ip
  end

  after(:all) do
    unbind_and_deprovision(@service_binding, @service_instance)
  end

  it 'restores data to the instance' do
    expect(@client.read("moaning")).to eq("myrtle")
  end

  it 'logs successful completion of restore' do
    msg = 'Redis data restore completed successfully'
    expect(contains_log_message(@vm_ip, @preprovision_timestamp, msg)).to be true
  end
end

shared_examples 'it errors when run as non-root user' do |plan|
  before(:all) do
    @service_instance, @service_binding = provision_and_bind plan
    @vm_ip = @service_binding.credentials[:host]
    @client = service_client_builder(@service_binding)
    expect(@client.read("moaning")).to_not eq("myrtle")
    @output = execute_restore_as_vcap (get_restore_args plan, @service_instance.id, BACKUP_PATH), @vm_ip
  end

  after(:all) do
    unbind_and_deprovision(@service_binding, @service_instance)
  end

  it 'logs that restore should be run as root' do
    msg = 'expected the script to be running as user `root`'
    expect(@output).to include msg
    expect(broker_registered?).to be true
  end
end

shared_examples 'it errors when file is on wrong device' do |plan|
  before(:all) do
    @service_instance, @service_binding, @vm_ip, @client = provision_and_build_service_client plan
    stage_dump_file_incorrectly @vm_ip
    expect(@client.read("moaning")).to_not eq("myrtle")

    tmp_backup_path = '/tmp/moaning-dump.rdb'
    @output = execute_restore_as_root (get_restore_args plan, @service_instance.id, tmp_backup_path), @vm_ip
  end

  after(:all) do
    root_execute_on(@vm_ip, 'rm /tmp/moaning-dump.rdb')
    unbind_and_deprovision(@service_binding, @service_instance)
  end

  it 'logs that the file should be in /var/vcap/store' do
    msg = 'Please move your rdb file to inside /var/vcap/store'
    expect(@output).to include msg
    expect(broker_registered?).to be true
  end
end

shared_examples 'it errors when passed an incorrect guid' do |plan|
  before(:all) do
    @service_instance, @service_binding, @vm_ip, @client = provision_and_build_service_client plan
    stage_dump_file @vm_ip
    expect(@client.read("moaning")).to_not eq("myrtle")

    @output = execute_restore_as_root "--sourceRDB #{BACKUP_PATH} --sharedVmGuid imafakeguid", @vm_ip
  end

  after(:all) do
    root_execute_on(@vm_ip, 'rm /tmp/moaning-dump.rdb')
    unbind_and_deprovision(@service_binding, @service_instance)
  end

  it 'logs that the file should be in /var/vcap/store' do
    msg = 'service-instance provided does not exist, please check you are on the correct VM and the instance guid is correct'
    expect(@output).to include msg
    expect(broker_registered?).to be true
  end
end


describe 'restore' do
  @broker_has_stopped_responding=false
  @restore_has_finished = false

  context 'shared-vm' do
    it_behaves_like 'it errors when run as non-root user', 'shared-vm'
    it_behaves_like 'it errors when file is on wrong device', 'shared-vm'
    it_behaves_like 'it errors when passed an incorrect guid', 'shared-vm'

    context 'with multiple redis servers running' do

      before do
        @service_instance1, @service_binding1, @vm_ip1, @client1 = provision_and_build_service_client "shared-vm"
        check_server_responding?(@client1)
        @service_instance2, @service_binding2, @vm_ip2, @client2 = provision_and_build_service_client "shared-vm"
        check_server_responding?(@client2)


        @service_instance, @service_binding, @vm_ip, @client = provision_and_build_service_client "shared-vm"
        stage_dump_file @vm_ip
        expect(@client.read("moaning")).to_not eq("myrtle")

        Thread.new { server_is_continually_alive?(@client1, @vm_ip1, "test_key", "test_value") }
        execute_restore_as_root (get_restore_args "shared-vm", @service_instance.id, BACKUP_PATH), @vm_ip
      end

      it 'keeps the broker and other redis servers alive while performing a restore' do
        expect(@client.read("moaning")).to eq("myrtle")
        expect(@broker_has_stopped_responding).to be false
      end

      after do
        unbind_and_deprovision(@service_binding, @service_instance)
        unbind_and_deprovision(@service_binding1, @service_instance1)
        unbind_and_deprovision(@service_binding2, @service_instance2)
      end
    end

  end

  context 'dedicated-vm' do
    it_behaves_like 'it can restore Redis', 'dedicated-vm'
    it_behaves_like 'it errors when run as non-root user', 'dedicated-vm'
    it_behaves_like 'it errors when file is on wrong device', 'dedicated-vm'
    it_behaves_like 'it errors when passed an incorrect guid', 'dedicated-vm'
  end
end

def provision_and_build_service_client plan
  service_instance, service_binding = provision_and_bind plan

  vm_ip = service_binding.credentials[:host]
  client = service_client_builder(service_binding)
  return service_instance, service_binding, vm_ip, client
end

def contains_log_message vm_ip, preprovision_timestamp,log_message
  vm_log = root_execute_on(vm_ip, "cat /var/vcap/sys/log/service-backup/restore.log")
  contains_expected_log = drop_log_lines_before(preprovision_timestamp, vm_log).any? do |line|
    line.include?(log_message)
  end
  contains_expected_log
end

def unbind_and_deprovision service_binding, service_instance
    service_broker.unbind_instance(service_binding)
    service_broker.deprovision_instance(service_instance)
end

def broker_registered?
  15.times do |n|
    return true if broker_available?

    sleep 1
  end

  puts "Timed out waiting for broker to respond"
  false
end

def broker_available?
  uri = URI.parse('https://' + bosh_manifest.property('broker.host') + '/v2/catalog')

  auth = {
    username: bosh_manifest.property("broker.username"),
    password: bosh_manifest.property("broker.password")
  }

  response = HTTParty.get(uri, verify: false, basic_auth: auth)

  response.code == 200
end

def stage_dump_file vm_ip
  local_dump = 'spec/fixtures/moaning-dump.rdb'
  ssh_gateway.scp_to(vm_ip, local_dump, '/tmp/moaning-dump.rdb')
  root_execute_on(vm_ip, "mv /tmp/moaning-dump.rdb #{BACKUP_PATH}")
end

def stage_dump_file_incorrectly vm_ip
  local_dump = 'spec/fixtures/moaning-dump.rdb'
  ssh_gateway.scp_to(vm_ip, local_dump, '/tmp/moaning-dump.rdb')
end

def get_restore_args plan, instance_id, source_rdb
  restore_args = "--sourceRDB #{source_rdb}"

  if plan == 'shared-vm'
    restore_args = "#{restore_args} --sharedVmGuid #{instance_id}"
  end

  restore_args
end

def provision_and_bind plan
  service_name = bosh_manifest.property('redis.broker.service_name')
  service_instance = service_broker.provision_instance(service_name, plan)
  service_binding  = service_broker.bind_instance(service_instance)
  return service_instance, service_binding
end

def execute_restore_as_vcap args, vm_ip
  ssh_gateway.execute_on(vm_ip, "#{RESTORE_BINARY} #{args}")
end

def execute_restore_as_root args, vm_ip
  root_execute_on(vm_ip, "#{RESTORE_BINARY} #{args}")
end

def server_is_continually_alive? client, vm_ip, key, value
  while !@restore_has_finished do
    @broker_has_stopped_responding = !other_redis_servers_alive?(vm_ip) || !broker_available?
    if @broker_has_stopped_responding
      return
    end

    sleep 0.5
  end
  return true
end

def check_server_responding? client
  client.write('test_key', 'test_value')
  expect(client.read('test_key')).to eq('test_value')
end

def other_redis_servers_alive? vm_ip
  response = root_execute_on(vm_ip, "ps aux | grep redis-serve[r] | wc -l")
  response.strip!
  response.to_i >= 2
end
