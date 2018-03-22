require 'system_spec_helper'
require 'httparty'

RESTORE_BINARY = '/var/vcap/jobs/redis-backups/bin/restore'
DUMP_FIXTURE_PATH = 'spec/fixtures/moaning-dump.rdb'
BACKUP_PATH = '/var/vcap/store/dump.rdb'
TEMP_COPY_PATH = '/tmp/moaning-dump.rdb'

shared_examples 'it errors when run as non-root user' do |plan|
  before(:all) do
    @service_instance, @service_binding, vm_ip, client = provision_and_build_service_client(plan)
    @instance_ssh = instance_ssh(vm_ip)

    expect(client.read("moaning")).to_not eq("myrtle")
  end

  after(:all) do
    unbind_and_deprovision(@service_binding, @service_instance)
  end

  it 'logs that restore should be run as root' do
    output = @instance_ssh.execute("#{RESTORE_BINARY} #{get_restore_args(plan, @service_instance.id, BACKUP_PATH)}")
    expect(output).to include('Permission denied').or include('Operation not permitted')
    expect(broker_registered?).to be true
  end
end

shared_examples 'it errors when file is on wrong device' do |plan|
  before(:all) do
    @service_instance, @service_binding, vm_ip, client = provision_and_build_service_client(plan)
    @instance_ssh = instance_ssh(vm_ip)

    @instance_ssh.copy(DUMP_FIXTURE_PATH, TEMP_COPY_PATH)
    expect(client.read("moaning")).to_not eq("myrtle")
  end

  after(:all) do
    @instance_ssh.execute('rm /tmp/moaning-dump.rdb')
    unbind_and_deprovision(@service_binding, @service_instance)
  end

  it 'logs that the file should be in /var/vcap/store' do
    output = @instance_ssh.execute("sudo #{RESTORE_BINARY} #{get_restore_args(plan, @service_instance.id, TEMP_COPY_PATH)}")
    expect(output).to include 'Please move your rdb file to inside /var/vcap/store'
    expect(broker_registered?).to be true
  end
end

shared_examples 'it errors when passed an incorrect guid' do |plan|
  before(:all) do
    @service_instance, @service_binding, vm_ip, client = provision_and_build_service_client(plan)
    @instance_ssh = instance_ssh(vm_ip)

    @instance_ssh.copy(DUMP_FIXTURE_PATH, TEMP_COPY_PATH)
    @instance_ssh.execute("sudo mv #{TEMP_COPY_PATH} #{BACKUP_PATH}")
    expect(client.read("moaning")).to_not eq("myrtle")
  end

  after(:all) do
    @instance_ssh.execute("rm /tmp/moaning-dump.rdb")
    unbind_and_deprovision(@service_binding, @service_instance)
  end

  it 'logs that the service instance provided does not exist' do
    output = @instance_ssh.execute("sudo #{RESTORE_BINARY} --sourceRDB #{BACKUP_PATH} --sharedVmGuid imafakeguid")
    expect(output).to include(
      'service-instance provided does not exist, please check you are on the correct VM and the instance guid is correct'
    )
    expect(broker_registered?).to be true
  end
end

describe 'restore' do
  context 'shared-vm' do
    it_behaves_like 'it errors when run as non-root user', 'shared-vm'
    it_behaves_like 'it errors when file is on wrong device', 'shared-vm'
    it_behaves_like 'it errors when passed an incorrect guid', 'shared-vm'

    context 'with multiple redis servers running' do
      before do
        plan = 'shared-vm'
        @other_instance1, @other_binding1, _, other_client1 = provision_and_build_service_client(plan)
        expect(check_server_responding?(other_client1)).to be true
        @other_instance2, @other_binding2, _, other_client2 = provision_and_build_service_client(plan)
        expect(check_server_responding?(other_client2)).to be true

        @service_instance, @service_binding, _, @client = provision_and_build_service_client(plan)
        broker_ssh.copy(DUMP_FIXTURE_PATH, TEMP_COPY_PATH)
        broker_ssh.execute("sudo mv #{TEMP_COPY_PATH} #{BACKUP_PATH}")
        expect(@client.read("moaning")).to_not eq("myrtle")

        @broker_has_stopped_responding = false
        @other_instances_have_stopped_responding = false
        @check_response_thread = Thread.new do
          loop do
            @broker_has_stopped_responding = !broker_available?
            @other_instances_have_stopped_responding =
              !check_server_responding?(other_client1) ||
              !check_server_responding?(other_client2)

            if @broker_has_stopped_responding || @other_instances_have_stopped_responding
              return
            end

            sleep 0.5
          end
        end

        broker_ssh.execute("sudo #{RESTORE_BINARY} #{get_restore_args(plan, @service_instance.id, BACKUP_PATH)}")
      end

      after do
        @check_response_thread.kill
        unbind_and_deprovision(@service_binding, @service_instance)
        unbind_and_deprovision(@other_binding1, @other_instance1)
        unbind_and_deprovision(@other_binding2, @other_instance2)
      end

      it 'keeps the broker and other redis servers alive while performing a restore' do
        expect(@client.read("moaning")).to eq("myrtle")
        expect(@broker_has_stopped_responding).to be false
        expect(@other_instances_have_stopped_responding).to be false
      end
    end
  end

  context 'dedicated-vm' do
    it_behaves_like 'it errors when run as non-root user', 'dedicated-vm'
    it_behaves_like 'it errors when file is on wrong device', 'dedicated-vm'
    it_behaves_like 'it errors when passed an incorrect guid', 'dedicated-vm'

    context 'it can restore Redis' do
      before(:all) do
        plan = 'dedicated-vm'
        @service_instance, @service_binding, vm_ip, @client = provision_and_build_service_client(plan)

        @node_ssh = instance_ssh(vm_ip)

        @node_ssh.copy(DUMP_FIXTURE_PATH, TEMP_COPY_PATH)
        @node_ssh.execute("sudo mv #{TEMP_COPY_PATH} #{BACKUP_PATH}")
        expect(@client.read("moaning")).to_not eq("myrtle")

        @prerestore_timestamp = @node_ssh.execute("date +%s")
        @node_ssh.execute("sudo #{RESTORE_BINARY} #{get_restore_args(plan, @service_instance.id, BACKUP_PATH)}")
      end

      after(:all) do
        unbind_and_deprovision(@service_binding, @service_instance)
      end

      it 'restores data to the instance' do
        expect(@client.read("moaning")).to eq("myrtle")

        vm_log = @node_ssh.execute("sudo cat /var/vcap/sys/log/service-backup/restore.log")
        contains_expected_log = drop_log_lines_before(@prerestore_timestamp, vm_log).any? do |line|
          line.include?('Redis data restore completed successfully')
        end
        expect(contains_expected_log).to be true
      end
    end
  end
end

def provision_and_build_service_client(plan)
  service_instance, service_binding = provision_and_bind(plan)

  vm_ip = service_binding.credentials[:host]
  client = service_client_builder(service_binding)
  return service_instance, service_binding, vm_ip, client
end

def unbind_and_deprovision(service_binding, service_instance)
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

def get_restore_args(plan, instance_id, source_rdb)
  restore_args = "--sourceRDB #{source_rdb}"

  if plan == 'shared-vm'
    restore_args = "#{restore_args} --sharedVmGuid #{instance_id}"
  end

  restore_args
end

def provision_and_bind(plan)
  service_name = bosh_manifest.property('redis.broker.service_name')
  service_instance = service_broker.provision_instance(service_name, plan)
  service_binding  = service_broker.bind_instance(service_instance)
  return service_instance, service_binding
end

def check_server_responding?(client)
  client.write('test_key', 'test_value')
  client.read('test_key') == 'test_value'
end
