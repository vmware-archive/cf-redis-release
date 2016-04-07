require 'system_spec_helper'

require 'aws-sdk'

describe 'backups' do
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

  let(:dump_file_pattern) { /dump-.*-\d{4}-\d{2}-\d{2}-\d{2}:\d{2}\.rdb/ }

  shared_examples "backups are enabled" do
    describe 'service backups', :skip_service_backups => true do
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
        let(:s3_client) do
          AWS::S3.new(
            access_key_id: aws_access_key_id,
            secret_access_key: aws_secret_access_key
          )
        end

        def find_s3_backup_file
          s3_client.buckets[s3_backup_bucket].objects.
            find_all { |object| object.key.include? "backup/#{Time.now.strftime("%Y/%m/%d")}" }.
            find { |object| object.key =~ dump_file_pattern }
        end

        def clean_s3_bucket
          s3_client.buckets[s3_backup_bucket].clear!
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
              result = vm_execute.call(manual_backup_command).lines.join
              expect(result).to match(/Perform backup completed without error/)
              expect(result).to match(/Upload backup completed without error/)
              expect(result).to match(/Cleanup completed without error/)
            end

            s3_backup_file = find_s3_backup_file
            expect(s3_backup_file).not_to eq(nil)
            expect(s3_backup_file.exists?).to eq(true)
            expect(s3_backup_file.content_length).not_to eq(0)

            contents = s3_backup_file.read
            expect(contents).to match(/^REDIS/)       # check RDB format
            expect(contents).to_not include('SELECT') # check not AOF format

            ls_result = vm_execute.call("ls #{source_folder}")
            expect(ls_result.lines.size).to eq(0)
          end
        end
      end

      describe 'manual snapshot' do
        it 'creates an RDB dump file' do
          with_remote_execution(service_name, service_plan) do |vm_execute|
            result = vm_execute.call(manual_snapshot_command)
            expect(result.lines.join).to(match('"event":"done","task":"create-snapshot"'), 'done event not found')

            ls_output = vm_execute.call("ls -l #{source_folder}dump-*.rdb")
            expect(ls_output.lines.size).to eql(1)
            expect(ls_output.lines.first).to match(/#{source_folder}#{dump_file_pattern}/)
          end
        end
      end

      describe 'manual cleanup' do
        it 'deletes the RDB dump file' do
          with_remote_execution(service_name, service_plan) do |vm_execute|
            filename = "dump-instance-2010-01-01-01:01.rdb"
            result = vm_execute.call("touch #{source_folder}/#{filename}; ls #{source_folder}")
            expect(result.lines.join).to match(filename)

            cleanup_result = vm_execute.call(manual_cleanup_command)
            expect(cleanup_result.lines.join).to match('"event":"done","task":"perform-cleanup"')

            ls_result = vm_execute.call("ls #{source_folder}")
            expect(ls_result.lines.join).to_not match(filename)
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
