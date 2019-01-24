require 'system_spec_helper'

require 'aws-sdk'
require 'digest'
require 'json'

describe 'backups', :skip_service_backups => true do
  MANUAL_BACKUP_CONFIG = '/var/vcap/jobs/service-backup/config/backup.yml'
  DUMP_FILE_PATTERN = /\d{8}T\d{6}Z-.*_redis_backup.rdb/

  let(:destinations) { bosh_manifest.property('service-backup.destinations') }
  let(:source_folder) { bosh_manifest.property('service-backup.source_folder') }
  let(:cron_schedule) { bosh_manifest.property('service-backup.cron_schedule') }
  let(:manual_cleanup_command) { bosh_manifest.property('service-backup.cleanup_executable') }
  let(:manual_snapshot_command) { bosh_manifest.property('service-backup.source_executable') }
  let(:manual_snapshot_log_file_path) { '/var/vcap/sys/log/service-backup/redis-backup.out.log' }
  let(:service_identifier_executable) { bosh_manifest.property('service-backup.service_identifier_executable') }
  let(:service_name) { bosh_manifest.property('redis.broker.service_name') }
  let(:s3_config) do
    destinations.select do |destination|
      destination['type'] == 's3'
    end.first['config']
  end

  shared_examples 'backups are enabled' do
    describe 'service backups' do
      context 'configuration' do
        let(:service_backup_config) do
          with_remote_execution(service_name, service_plan) do |vm_execute|
            config_cmd = "sudo cat #{MANUAL_BACKUP_CONFIG}"
            YAML.load(vm_execute.call(config_cmd).gsub(/"/, ''))
          end
        end

        it 'service backups is configured correctly' do
          with_remote_execution(service_name, service_plan) do |_, service_binding|
            with_redis_under_stress(service_binding) do
              expected_backup_config = {
                "service_identifier_executable" => service_identifier_executable,
                "source_executable" => manual_snapshot_command,
                "cron_schedule" => cron_schedule,
                "cleanup_executable" => manual_cleanup_command,
                "source_folder" => source_folder
              }

              expect(service_backup_config).to include(expected_backup_config)
            end
          end
        end

        context 'destinations' do
          context 's3' do
            it 'is configured correctly' do
              with_remote_execution(service_name, service_plan) do |service_binding|
                with_redis_under_stress(service_binding) do
                  expected_backup_config = {
                    "type" => 's3',
                    "config" => {
                      "endpoint_url" => s3_config['endpoint_url'],
                      "access_key_id" => s3_config['access_key_id'],
                      "secret_access_key" => s3_config['secret_access_key'],
                      "bucket_name" => s3_config['bucket_name'],
                      "bucket_path" => s3_config['bucket_path'],
                      "region" => ''
                    }
                  }

                  expect(service_backup_config['destinations']).to include(expected_backup_config)
                end
              end
            end
          end
        end
      end

      describe 'manual snapshot' do
        before do
          with_remote_execution(service_name, service_plan) do |vm_execute|
            clear_snapshot_logs_result = vm_execute.call("sudo truncate -s 0 #{manual_snapshot_log_file_path}")
            expect(clear_snapshot_logs_result).to be_empty
          end
        end

        after do
          with_remote_execution(service_name, service_plan) do |vm_execute|
            cleanup_result = vm_execute.call("sudo #{manual_cleanup_command}")
            expect(cleanup_result).to_not be_empty
            expect(cleanup_result).to match('"event":"done","task":"perform-cleanup"')
          end
        end

        it 'creates an RDB dump file' do
          with_remote_execution(service_name, service_plan) do |vm_execute|
            result = vm_execute.call("sudo #{manual_snapshot_command}")
            expect(result.strip).to_not be_empty
            task_line = result.lines.select { |line|
              line.include?('"task":"create-snapshot"') && line.include?('"event":"done"')
            }
            expect(task_line.length).to be > 0, 'done event not found'

            log_output = vm_execute.call("sudo cat #{manual_snapshot_log_file_path}")
            expect(log_output).to_not be_empty
            expected_log = log_output.lines.select { |line|
              line.include?('"task":"create-snapshot"') && line.include?('"event":"done"')
            }
            expect(expected_log.length).to be > 0

            ls_output = vm_execute.call("sudo ls -l #{source_folder}*redis_backup.rdb")
            expect(ls_output).to_not be_empty
            expect(ls_output.lines.size).to eql(1)
            expect(ls_output.lines.first).to match(/#{source_folder}#{DUMP_FILE_PATTERN}/)
          end
        end
      end

      describe 'manual cleanup' do
        it 'deletes the RDB dump file' do
          with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
            instance_id = service_binding.service_instance.id
            filename = "20100101T010100Z-#{instance_id}_#{service_plan}_redis_backup.rdb"

            assert_manual_cleanup_succeeds(vm_execute, filename)
          end
        end

        it 'deletes the md5 files' do
          with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
            instance_id = service_binding.service_instance.id
            filename = "20100101T010100Z-#{instance_id}_#{service_plan}_redis_backup.md5"

            assert_manual_cleanup_succeeds(vm_execute, filename)
          end
        end
      end
    end
  end

  shared_examples 'data and broker state is backed up' do
    describe 'end to end' do
      let(:s3_client) { Aws::S3::Client.new }

      before do
        clean_s3_bucket
      end

      after do
        clean_s3_bucket
      end

      it 'uploads backup artifacts to S3 in the correct formats and removes local backup files' do
        with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
          client = service_client_builder(service_binding)
          client.write('foo', 'bar')
          with_redis_under_stress(service_binding) do
            assert_manual_backup_succeeds(vm_execute, service_binding)
          end

          assert_rdb_file_is_valid

          s3_statefile = find_s3_statefile
          s3_statefile_contents = get_raw_file_contents s3_statefile
          expect{JSON.parse(s3_statefile_contents)}.to_not raise_error
          statefile_json = JSON.parse(s3_statefile_contents)
          expect(statefile_json.keys).to contain_exactly('available_instances',
                                                         'allocated_instances',
                                                         'instance_bindings')

          assert_statefile_is_valid

          ls_result = vm_execute.call("sudo ls #{source_folder}")
          expect(ls_result).to be_empty
        end
      end
    end
  end

  shared_examples 'only data is backed up' do
    describe 'end to end' do
      let(:s3_client) { Aws::S3::Client.new }

      before do
        clean_s3_bucket
      end

      after do
        clean_s3_bucket
      end

      it 'uploads data to S3 in RDB format and removes local backup files' do
        with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
          client = service_client_builder(service_binding)
          client.write('foo', 'bar')
          with_redis_under_stress(service_binding) do
            assert_manual_backup_succeeds(vm_execute, service_binding)
          end

          assert_rdb_file_is_valid

          s3_statefile = find_s3_statefile
          expect(s3_statefile).to be_nil

          ls_result = vm_execute.call("sudo ls #{source_folder}")
          expect(ls_result).to be_empty
        end
      end
    end
  end

  describe 'instance identifier' do
    context 'with a provisioned dedicated-vm plan' do
      let(:service_plan) { 'dedicated-vm' }

      it 'returns the correct instance ID' do
        with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
          id = vm_execute.call("sudo #{service_identifier_executable}")
          expect(id).to match(service_binding.service_instance.id)
        end
      end
    end

    context 'with provisioned shared-vm plan' do
      let(:service_plan) { 'shared-vm' }

      it 'returns the correct instance IDs' do
        with_remote_execution(service_name, service_plan) do |_, service_binding1|
          with_remote_execution(service_name, service_plan) do |vm_execute, service_binding2|
            instance_ids = vm_execute.call("sudo #{service_identifier_executable}")
            expect(instance_ids).to match(service_binding1.service_instance.id)
            expect(instance_ids).to match(service_binding2.service_instance.id)
          end
        end
      end
    end
  end

  context 'shared vm plan' do
    let(:service_plan) { 'shared-vm' }
    it_behaves_like 'backups are enabled'
    it_behaves_like 'data and broker state is backed up'
  end

  context 'dedicated vm plan' do
    let(:service_plan) { 'dedicated-vm' }
    it_behaves_like 'backups are enabled'
    it_behaves_like 'only data is backed up'
  end

  def with_remote_execution(service_name, service_plan)
    service_broker.provision_and_bind(service_name, service_plan) do |service_binding|
      host = service_binding.credentials[:host]
      instance_ssh = instance_ssh(host)

      vm_execute = Proc.new do |command|
        instance_ssh.execute(command)
      end
      yield vm_execute, service_binding
    end
  end

  def with_repeated_action(service_binding, action)
    runner = Thread.new do
      begin
        client = service_client_builder(service_binding)
        counter = 0
        while true
          action.call(client, counter)
          counter += 1
        end
      rescue Exception => e
        puts 'Caught exception while running repeated action',
          e.message,
          e.backtrace
      end
    end

    sleep 1

    yield

    Thread.kill(runner)
  end

  def with_redis_under_stress(service_binding)
    action = proc do |client, counter|
      random_string = (0...5000).map { ('a'..'z').to_a[rand(26)] }.join
      client.write counter.to_s, random_string
    end

    with_repeated_action(service_binding, action) { yield }

    service_client_builder(service_binding)
  end

  def find_s3_backup_file
    find_s3_file DUMP_FILE_PATTERN
  end

  def find_s3_statefile
    find_s3_file /\d{8}T\d{6}Z_.+_statefile.json/
  end

  def find_s3_backup_file_md5
    find_s3_file /\d{8}T\d{6}Z-.*_redis_backup.md5/
  end

  def find_s3_statefile_md5
    find_s3_file /\d{8}T\d{6}Z_.+_statefile.md5/
  end

  def find_s3_file(file_pattern)
    s3_backup_file_meta = s3_client.list_objects(bucket: s3_config['bucket_name']).contents.
      find_all { |object| object.key.include? "backup/#{Time.now.strftime("%Y/%m/%d")}" }.
      find { |object| object.key =~ file_pattern }
    return nil if s3_backup_file_meta.nil?
    s3_client.get_object(bucket: s3_config['bucket_name'], key: s3_backup_file_meta.key).body
  end

  def clean_s3_bucket
    Aws::S3::Bucket.new(name: s3_config['bucket_name'], client: s3_client).clear!
  end

  def get_raw_file_contents(s3_file)
    expect(s3_file).not_to be_nil
    expect(s3_file.size).to be > 0
    s3_file.string
  end

  def get_utf8_file_contents(s3_file)
    expect(s3_file).not_to be_nil
    expect(s3_file.size).to be > 0
    s3_file.read.encode('UTF-8', 'UTF-8', :invalid => :replace)
  end

  def assert_manual_backup_succeeds(vm, service_binding)
    cmd_result = vm.call("sudo /var/vcap/packages/service-backup/bin/manual-backup #{MANUAL_BACKUP_CONFIG}")
    expect(cmd_result).to_not be_empty

    expect(cmd_result).to match(/Perform backup completed successfully/)
    expect(cmd_result).to match(/Upload backup completed successfully/)
    expect(cmd_result).to match(/Cleanup completed successfully/)
    expect(cmd_result).to include("#{service_plan}: #{service_binding.service_instance.id}")
  end

  def assert_rdb_file_is_valid
    s3_backup_file = find_s3_backup_file
    s3_backup_file_contents = get_raw_file_contents s3_backup_file
    s3_backup_file_contents_utf8 = get_utf8_file_contents s3_backup_file
    s3_backup_file_md5 = find_s3_backup_file_md5
    s3_backup_file_md5_contents = get_raw_file_contents s3_backup_file_md5

    expect(s3_backup_file_contents_utf8).to match(/^REDIS/)       # check RDB format
    expect(s3_backup_file_contents_utf8).to_not include('SELECT') # check not AOF format

    file_md5 = Digest::MD5.hexdigest s3_backup_file_contents
    expect(file_md5).to eq(s3_backup_file_md5_contents)
  end

  def assert_statefile_is_valid
    s3_statefile = find_s3_statefile
    s3_statefile_contents = get_raw_file_contents s3_statefile
    s3_statefile_md5 = find_s3_statefile_md5
    s3_statefile_md5_contents = get_raw_file_contents s3_statefile_md5

    state_md5 = Digest::MD5.hexdigest s3_statefile_contents
    expect(state_md5).to eq(s3_statefile_md5_contents)
  end
end

def assert_manual_cleanup_succeeds(vm_execute, filename)
  result = vm_execute.call("sudo touch #{source_folder}/#{filename}; ls #{source_folder}")
  expect(result).to_not be_empty
  expect(result).to match(filename)

  cleanup_result = vm_execute.call("sudo #{manual_cleanup_command}")
  expect(cleanup_result).to_not be_empty
  expect(cleanup_result).to match('"event":"done","task":"perform-cleanup"')

  ls_result = vm_execute.call("sudo ls #{source_folder}")
  expect(ls_result).to_not match(filename)
end
