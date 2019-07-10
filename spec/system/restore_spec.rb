require 'system_spec_helper'
require 'httparty'

RESTORE_BINARY = '/var/vcap/jobs/redis-backups/bin/restore'
DUMP_FIXTURE_PATH = 'spec/fixtures/moaning-dump.rdb'
BACKUP_PATH = '/var/vcap/store/dump.rdb'
TEMP_COPY_PATH = '/tmp/moaning-dump.rdb'

def bosh
  Helpers::Bosh2.new
end

shared_examples 'it errors when run as non-root user' do |service_plan_name|
  before(:all) do
    @service_instance, @service_binding, vm_ip, client = provision_and_build_service_client(service_plan_name)
    @instance = bosh.instance(deployment_name, vm_ip)

    expect(client.read('moaning')).to_not eq('myrtle')
  end

  after(:all) do
    unbind_and_deprovision(@service_binding, @service_instance, service_plan_name)
  end

  it 'logs that restore should be run as root' do
    output, = bosh.ssh_with_error(deployment_name, @instance, "#{RESTORE_BINARY} #{get_restore_args(service_plan_name, @service_instance.id, BACKUP_PATH)}")
    expect(output).to include('Permission denied')
      .or include('Operation not permitted')
      .or include('No changes were performed')
    expect(broker_registered?).to be true
  end
end

shared_examples 'it errors when file is on wrong device' do |service_plan_name|
  before(:all) do
    @service_instance, @service_binding, vm_ip, client = provision_and_build_service_client(service_plan_name)
    @instance = bosh.instance(deployment_name, vm_ip)

    bosh.scp(deployment_name, @instance, DUMP_FIXTURE_PATH, TEMP_COPY_PATH)
    expect(client.read('moaning')).to_not eq('myrtle')
  end

  after(:all) do
    bosh.ssh(deployment_name, @instance, 'rm /tmp/moaning-dump.rdb')
    unbind_and_deprovision(@service_binding, @service_instance, service_plan_name)
  end

  it 'logs that the file should be in /var/vcap/store' do
     output, = bosh.ssh_with_error(deployment_name, @instance, "sudo #{RESTORE_BINARY} #{get_restore_args(service_plan_name, @service_instance.id, TEMP_COPY_PATH)}")
    expect(output).to include 'Please move your rdb file to inside /var/vcap/store'
    expect(broker_registered?).to be true
  end
end

shared_examples 'it errors when passed an incorrect guid' do |service_plan_name|
  before(:all) do
    @service_instance, @service_binding, vm_ip, client = provision_and_build_service_client(service_plan_name)
    @instance = bosh.instance(deployment_name, vm_ip)

    bosh.scp(deployment_name, @instance, DUMP_FIXTURE_PATH, TEMP_COPY_PATH)
    bosh.ssh(deployment_name, @instance, "sudo mv #{TEMP_COPY_PATH} #{BACKUP_PATH}")
    expect(client.read('moaning')).to_not eq('myrtle')
  end

  after(:all) do
    bosh.ssh_with_error(deployment_name, @instance, 'rm /var/vcap/store/dump.rdb')
    unbind_and_deprovision(@service_binding, @service_instance, service_plan_name)
  end

  it 'logs that the service instance provided does not exist' do
    output, = bosh.ssh_with_error(deployment_name, @instance, "sudo #{RESTORE_BINARY} --sourceRDB #{BACKUP_PATH} --sharedVmGuid imafakeguid")
    expect(output).to include(
      'No changes were performed. Problem with redis config'
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
      service_plan_name = 'shared-vm'

      before do
        @other_instance1, @other_binding1, _, other_client1 = provision_and_build_service_client(service_plan_name)
        expect(check_server_responding?(other_client1)).to be true
        @other_instance2, @other_binding2, _, other_client2 = provision_and_build_service_client(service_plan_name)
        expect(check_server_responding?(other_client2)).to be true

        @service_instance, @service_binding, _, @client = provision_and_build_service_client(service_plan_name)
        bosh.scp(deployment_name, Helpers::Environment::BROKER_JOB_NAME, DUMP_FIXTURE_PATH, TEMP_COPY_PATH)
        bosh.ssh(deployment_name, Helpers::Environment::BROKER_JOB_NAME, "sudo mv #{TEMP_COPY_PATH} #{BACKUP_PATH}")
        expect(@client.read('moaning')).to_not eq('myrtle')

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

        bosh.ssh(deployment_name, Helpers::Environment::BROKER_JOB_NAME, "sudo #{RESTORE_BINARY} #{get_restore_args(service_plan_name, @service_instance.id, BACKUP_PATH)}")
      end

      after do
        @check_response_thread.kill
        unbind_and_deprovision(@service_binding, @service_instance, service_plan_name)
        unbind_and_deprovision(@other_binding1, @other_instance1, service_plan_name)
        unbind_and_deprovision(@other_binding2, @other_instance2, service_plan_name)
      end

      it 'keeps the broker and other redis servers alive while performing a restore' do
        expect(@client.read('moaning')).to eq('myrtle')
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
      service_plan_name = 'dedicated-vm'

      before(:all) do
        @service_instance, @service_binding, vm_ip, @client = provision_and_build_service_client(service_plan_name)

        @instance = bosh.instance(deployment_name, vm_ip)

        bosh.scp(deployment_name, @instance, DUMP_FIXTURE_PATH, TEMP_COPY_PATH)
        bosh.ssh(deployment_name, @instance, "sudo mv #{TEMP_COPY_PATH} #{BACKUP_PATH}")
        expect(@client.read('moaning')).to_not eq('myrtle')

        @prerestore_timestamp = bosh.ssh(deployment_name, @instance, 'date +%s')
        bosh.ssh(deployment_name, @instance, "sudo #{RESTORE_BINARY} #{get_restore_args(service_plan_name, @service_instance.id, BACKUP_PATH)}")
      end

      after(:all) do
        unbind_and_deprovision(@service_binding, @service_instance, service_plan_name)
      end

      it 'restores data to the instance' do
        expect(@client.read('moaning')).to eq('myrtle')

        vm_log = bosh.ssh(deployment_name, @instance, 'sudo cat /var/vcap/sys/log/service-backup/restore.log')
        contains_expected_log = drop_log_lines_before(@prerestore_timestamp, vm_log).any? do |line|
          line.include?('Redis data restore completed successfully')
        end
        expect(contains_expected_log).to be true
      end
    end
  end
end

def provision_and_build_service_client(service_plan_name)
  service_instance, service_binding = provision_and_bind(service_plan_name)

  vm_ip = service_binding.credentials[:host]
  client = service_client_builder(service_binding)
  [service_instance, service_binding, vm_ip, client]
end

def unbind_and_deprovision(service_binding, service_instance, service_plan_name)
  service_name = test_manifest['properties']['redis']['broker']['service_name']

  service_broker.unbind_instance(service_binding, service_name, service_plan_name)
  service_broker.deprovision_instance(service_instance, service_name, service_plan_name)
end

def broker_registered?
  15.times do
    return true if broker_available?

    sleep 1
  end

  puts 'Timed out waiting for broker to respond'
  false
end

def broker_available?
  uri = URI.parse('https://' + test_manifest['properties']['broker']['host'] + '/v2/catalog')

  auth = {
    username: test_manifest['properties']['broker']['username'],
    password: test_manifest['properties']['broker']['password']
  }

  response = HTTParty.get(uri, verify: false, headers: {'X-Broker-API-Version' => '2.13'}, basic_auth: auth)

  response.code == 200
end

def get_restore_args(service_plan_name, instance_id, source_rdb)
  restore_args = "--sourceRDB #{source_rdb}"

  if service_plan_name == 'shared-vm'
    restore_args = "#{restore_args} --sharedVmGuid #{instance_id}"
  end

  restore_args
end

def provision_and_bind(service_plan_name)
  service_name = test_manifest['properties']['redis']['broker']['service_name']
  service_instance = service_broker.provision_instance(service_name, service_plan_name)
  service_binding  = service_broker.bind_instance(service_instance, service_name, service_plan_name)
  [service_instance, service_binding]
end

def check_server_responding?(client)
  client.write('test_key', 'test_value')
  client.read('test_key') == 'test_value'
end
