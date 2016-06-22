require 'system_spec_helper'

require 'aws-sdk'

describe 'backups', :skip_service_backups => true do
  let(:source_folder) { bosh_manifest.property("service-backup.source_folder") }
  let(:service_name) { bosh_manifest.property('redis.broker.service_name') }
  let(:aws_access_key_id) { bosh_manifest.property('service-backup.destination.s3.access_key_id') }
  let(:aws_secret_access_key) { bosh_manifest.property('service-backup.destination.s3.secret_access_key') }
  let(:s3_backup_bucket) { bosh_manifest.property("service-backup.destination.s3.bucket_name") }
  let(:s3_backup_path) { bosh_manifest.property("service-backup.destination.s3.bucket_path") }

  let(:identifier_command) do
    '/var/vcap/packages/redis-backups/bin/identifier -config /var/vcap/jobs/redis-backups/config/backup-config.yml'
  end

  let(:manual_snapshot_command) do
    '/var/vcap/packages/redis-backups/bin/snapshot -config /var/vcap/jobs/redis-backups/config/backup-config.yml'
  end

  let(:manual_cleanup_command) do
    '/var/vcap/packages/redis-backups/bin/cleanup -config /var/vcap/jobs/redis-backups/config/backup-config.yml'
  end

  let(:manual_backup_command) do
    "/var/vcap/packages/service-backup/bin/manual-backup s3 " \
    "--cron-schedule '0 0 * * *' " \
    "--backup-creator-cmd '#{manual_snapshot_command}' " \
    "--source-folder '#{source_folder}' " \
    "--cleanup-cmd '#{manual_cleanup_command}' " \
    "--dest-path '#{s3_backup_path}' " \
    "--aws-access-key-id #{aws_access_key_id} " \
    "--aws-secret-access-key #{aws_secret_access_key} " \
    "--endpoint-url 'https://s3.amazonaws.com' " \
    "--aws-cli-path '/var/vcap/packages/aws-cli/bin/aws' " \
    "--dest-bucket '#{s3_backup_bucket}'"
  end

  let(:dump_file_pattern) { /\d{8}T\d{6}Z-.*_redis_backup.rdb/ }

  shared_examples "backups are enabled" do
    describe 'service backups' do
      it 'is configured correctly' do
        with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
          with_redis_under_stress(service_binding) do
            cmd = vm_execute.call('ps aux | grep service-backup | grep -v grep')
              .split(' ').drop(10).join(' ').split('--')
              .map{|line| line.strip.partition(' ')}
              .each_with_object({}) {|e, hash| hash[e[0]] = e[-1]}

            expect(cmd['/var/vcap/packages/service-backup/bin/service-backup']).to eq('s3')
            expect(cmd['source-folder']).to eq(source_folder)
            expect(cmd['backup-creator-cmd']).to eq(manual_snapshot_command)
            expect(cmd['cron-schedule']).to eq('0 0 * * *')
            expect(cmd['dest-path']).to eq(s3_backup_path)
            expect(cmd['dest-bucket']).to eq(s3_backup_bucket)
            expect(cmd['aws-access-key-id']).to eq(aws_access_key_id)
            expect(cmd['aws-secret-access-key']).to eq(aws_secret_access_key)
            expect(cmd['cleanup-cmd']).to eq(manual_cleanup_command)
          end
        end
      end

      describe 'end to end' do
        let(:s3_client) { Aws::S3::Client.new }

        def find_s3_backup_file
          s3_backup_file_meta = s3_client.list_objects(bucket: s3_backup_bucket).contents.
            find_all { |object| object.key.include? "backup/#{Time.now.strftime("%Y/%m/%d")}" }.
            find { |object| object.key =~ dump_file_pattern }
          return nil if s3_backup_file_meta.nil?
          s3_client.get_object(bucket: s3_backup_bucket, key: s3_backup_file_meta.key).body
        end

        def clean_s3_bucket
          Aws::S3::Bucket.new(name: s3_backup_bucket, client: s3_client).clear!
        end

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
              cmd_result = vm_execute.call(manual_backup_command)
              expect(cmd_result).to_not be_nil

              result = cmd_result.lines.join
              expect(result).to match(/Perform backup completed successfully/)
              expect(result).to match(/Upload backup completed successfully/)
              expect(result).to match(/Cleanup completed successfully/)
            end

            s3_backup_file = find_s3_backup_file
            expect(s3_backup_file).not_to be_nil
            expect(s3_backup_file.size).to be > 0

            contents = s3_backup_file.read.encode('UTF-8', 'UTF-8', :invalid => :replace)
            expect(contents).to match(/^REDIS/)       # check RDB format
            expect(contents).to_not include('SELECT') # check not AOF format

            ls_result = vm_execute.call("ls #{source_folder}")
            expect(ls_result).to be_nil
          end
        end
      end

      describe 'manual snapshot' do
        it 'creates an RDB dump file' do
          with_remote_execution(service_name, service_plan) do |vm_execute|
            result = vm_execute.call(manual_snapshot_command)
            expect(result).to_not be_nil

            task_line = result.lines.select { |line|
              line.include?('"task":"create-snapshot"') && line.include?('"event":"done"')
            }

            expect(task_line.length).to be > 0, 'done event not found'

            ls_output = vm_execute.call("ls -l #{source_folder}*redis_backup.rdb")
            expect(ls_output).to_not be_nil
            expect(ls_output.lines.size).to eql(1)
            expect(ls_output.lines.first).to match(/#{source_folder}#{dump_file_pattern}/)
          end
        end
      end

      describe 'manual cleanup' do
        it 'deletes the RDB dump file' do
          with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
            instance_id = service_binding.service_instance.id
            filename = "20100101T010100Z-#{instance_id}_#{service_plan}_redis_backup.rdb"

            result = vm_execute.call("touch #{source_folder}/#{filename}; ls #{source_folder}")
            expect(result).to_not be_nil
            expect(result.lines.join).to match(filename)

            cleanup_result = vm_execute.call(manual_cleanup_command)
            expect(cleanup_result).to_not be_nil
            expect(cleanup_result.lines.join).to match('"event":"done","task":"perform-cleanup"')

            ls_result = vm_execute.call("ls #{source_folder}")
            expect(ls_result.lines.join).to_not match(filename) unless ls_result.nil?
          end
        end
      end
    end
  end

  describe "instance identifier" do
    context "with a provisioned dedicated-vm plan" do
      let(:service_plan) { 'dedicated-vm' }

      it 'returns the correct instance ID' do
        with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
          id = vm_execute.call(identifier_command)
          expect(id).to match(service_binding.service_instance.id)
        end
      end
    end

    context "with provisioned shared-vm plan" do
      let(:service_plan) { 'shared-vm' }

      it "returns the correct instance IDs" do
        with_remote_execution(service_name, service_plan) do |_, service_binding1|
          with_remote_execution(service_name, service_plan) do |vm_execute, service_binding2|
            instance_ids = vm_execute.call(identifier_command)
            expect(instance_ids).to match(service_binding1.service_instance.id)
            expect(instance_ids).to match(service_binding2.service_instance.id)
          end
        end
      end
    end
  end

  context "shared vm plan" do
    let(:service_plan) { 'shared-vm' }
    it_behaves_like 'backups are enabled'
  end

  context "dedicated vm plan" do
    let(:service_plan) { 'dedicated-vm' }
    it_behaves_like 'backups are enabled'
  end

  def with_remote_execution(service_name, service_plan, &block)
    service_broker.provision_and_bind(service_name, service_plan) do |service_binding|
      vm_execute = Proc.new {|command| ssh_gateway.execute_on(service_binding.credentials[:host], command)}
      block.call(vm_execute, service_binding)
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
        puts "Caught exception while running repeated action",
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
end
