require 'system_spec_helper'

require 'aws-sdk'

describe 'backups', :skip_service_backups => true do
  let(:destinations) { bosh_manifest.property("service-backup.destinations") }
  let(:s3_config) do
    destinations.select do |destination|
      destination["type"] == "s3"
    end.first["config"]
  end

  let(:source_folder) { bosh_manifest.property("service-backup.source_folder") }
  let(:cron_schedule) { bosh_manifest.property("service-backup.cron_schedule") }
  let(:manual_cleanup_command) { bosh_manifest.property("service-backup.cleanup_executable") }
  let(:manual_snapshot_command) { bosh_manifest.property("service-backup.source_executable") }
  let(:service_identifier_executable) { bosh_manifest.property("service-backup.service_identifier_executable") }
  let(:service_name) { bosh_manifest.property('redis.broker.service_name') }
  let(:aws_access_key_id) { s3_config["access_key_id"] }
  let(:aws_secret_access_key) { s3_config["secret_access_key"] }
  let(:s3_backup_bucket) { s3_config["bucket_name"] }
  let(:s3_backup_path) { s3_config["bucket_path"] }
  let(:endpoint_url) { s3_config["endpoint_url"] }

  let(:manual_backup_config) { "/var/vcap/jobs/service-backup/config/backup.yml" }
  let(:manual_backup_command) { "/var/vcap/packages/service-backup/bin/manual-backup #{manual_backup_config}" }

  let(:dump_file_pattern) { /\d{8}T\d{6}Z-.*_redis_backup.rdb/ }

  shared_examples "backups are enabled" do
    describe 'service backups' do
      context 'configuration' do
        let(:service_backup_config) do
          with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
            configCmd = "cat #{manual_backup_config}"
            YAML.load(vm_execute.call(configCmd).gsub(/"/, ''))
          end
        end

        it 'service backups is configured correctly' do
          with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
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
              with_remote_execution(service_name, service_plan) do |vm_execute, service_binding|
                with_redis_under_stress(service_binding) do
                  expected_backup_config = {
                    "type" => "s3",
                    "config" => {
                      "endpoint_url" => endpoint_url,
                      "access_key_id" => aws_access_key_id,
                      "secret_access_key" => aws_secret_access_key,
                      "bucket_name" => s3_backup_bucket,
                      "bucket_path" => s3_backup_path}
                  }

                  expect(service_backup_config["destinations"]).to include(expected_backup_config)
                end
              end
            end
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
              expect(result).to include("#{service_plan}: #{service_binding.service_instance.id}")
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
        after do
          with_remote_execution(service_name, service_plan) do |vm_execute|
            cleanup_result = vm_execute.call(manual_cleanup_command)
            expect(cleanup_result).to_not be_nil
            expect(cleanup_result.lines.join).to match('"event":"done","task":"perform-cleanup"')
          end
        end

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
          id = vm_execute.call(service_identifier_executable)
          expect(id).to match(service_binding.service_instance.id)
        end
      end
    end

    context "with provisioned shared-vm plan" do
      let(:service_plan) { 'shared-vm' }

      it "returns the correct instance IDs" do
        with_remote_execution(service_name, service_plan) do |_, service_binding1|
          with_remote_execution(service_name, service_plan) do |vm_execute, service_binding2|
            instance_ids = vm_execute.call(service_identifier_executable)
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
