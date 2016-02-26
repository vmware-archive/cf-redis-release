require 'system_spec_helper'

require 'aws-sdk'

require 'prof/marketplace_service'

describe 'backups' do

  let(:redis_config_command) { bosh_manifest.property("redis.config_command") }
  let(:broker_vm_ip) { bosh_director.ips_for_job('cf-redis-broker', bosh_manifest.deployment_name).first }
  let(:aws_access_key_id) { bosh_manifest.property("service-backup.destination.s3.access_key_id") }
  let(:aws_secret_access_key) { bosh_manifest.property("service-backup.destination.s3.secret_access_key") }

  let(:s3_client) {
    AWS::S3.new(
      access_key_id: aws_access_key_id,
      secret_access_key: aws_secret_access_key
    )
  }
  let(:s3_backup_bucket) { bosh_manifest.property("service-backup.destination.s3.bucket_name") }
  let(:s3_backup_path) { bosh_manifest.property("service-backup.destination.s3.bucket_path") }

  let(:test_key) { "test_key" }
  let(:test_value) { "test_value" }

  let(:destination_folder) { bosh_manifest.property("service-backup.source_folder") }

  let(:manual_backup_command) do
    "/var/vcap/packages/service-backup/bin/manual-backup s3 " +
      "--backup-creator-cmd '#{manual_snapshot_command}' " +
      "--source-folder '#{destination_folder}' " +
      "--cleanup-cmd '' " +
      "--dest-path '#{s3_backup_path}' " +
      "--aws-access-key-id '#{aws_access_key_id}' " +
      "--aws-secret-access-key '#{aws_secret_access_key}' " +
      "--aws-cli-path /var/vcap/packages/aws-cli/bin/aws " +
      "--dest-bucket '#{s3_backup_bucket}' " +
      "--endpoint-url 'https://s3.amazonaws.com/' "
  end
  let(:manual_snapshot_command) do
    '/var/vcap/packages/redis-backups/bin/snapshot ' +
      '-config /var/vcap/jobs/redis-backups/config/backup-config.yml'
  end
  let(:manual_cleanup_command) do
    '/var/vcap/packages/redis-backups/bin/cleanup ' +
      '-config /var/vcap/jobs/redis-backups/config/backup-config.yml'
  end

  context "shared vm plan" do
    let(:redis_save_command) { bosh_manifest.property("redis.save_command") }

    describe 'service backups', :skip_service_backups => true do
      let(:service) {
        Prof::MarketplaceService.new(
          name: bosh_manifest.property('redis.broker.service_name'),
          plan: 'shared-vm'
        )
      }

      describe 'manual snapshot', :skip_service_backups => true do
        it 'creates a dump.rdb file' do
          service_broker.provision_and_bind(service.name, service.plan) do |service_binding, service_instance|
            vm_ip = service_binding.credentials[:host]
            result = ssh_gateway.execute_on(
              vm_ip,
              manual_snapshot_command
            )
            expect(result.lines.join).to(match('"event":"done","task":"create-snapshot"'), 'done event not found')

            ls_output = ssh_gateway.execute_on(
              vm_ip, "ls -l #{destination_folder}dump.rdb"
            )
            expect(ls_output.lines.size).to(eql(1))
            expect(ls_output.lines.first).to_not(match('No such file or directory'))
            expect(ls_output.lines.first).to(match("#{destination_folder}dump.rdb"))
          end
        end
      end

      describe 'manual backup' do
        before do
          instance_id = create_backup_for_service(service)

          @s3_backup_file = s3_client.buckets[s3_backup_bucket].objects.
            find_all {|object| object.key.include? "backup/#{Time.now.strftime("%Y/%m/%d")}"}.
            find { |object| "dump.rdb" }
        end

        after do
          @s3_backup_file.delete if @s3_backup_file
        end

        it 'uploads data to S3 in RDB format' do
          expect(@s3_backup_file.exists?).to eq(true)
          expect(@s3_backup_file.content_length).not_to eq(0)
          contents = @s3_backup_file.read

          # check RDB format
          expect(contents).to match(/^REDIS/)

          # check not AOF format
          expect(contents).to_not include('SELECT')
        end
      end

      describe 'manual cleanup' do
        it 'deletes the dump.rdb file' do
          service_broker.provision_and_bind(service.name, service.plan) do |service_binding, service_instance|
            vm_ip = service_binding.credentials[:host]
            result = ssh_gateway.execute_on(
              vm_ip,
              "touch #{destination_folder}/dump.rdb; ls #{destination_folder}"
            )
            expect(result.lines.join).to match("dump.rdb")

            cleanup_result = ssh_gateway.execute_on(
              vm_ip,
              manual_cleanup_command
            )
            expect(cleanup_result.lines.join).to match('"event":"done","task":"perform-cleanup"')

            ls_result = ssh_gateway.execute_on(
              vm_ip,
              "ls #{destination_folder}"
            )
            expect(ls_result.lines.join).to_not match("dump.rdb")
          end
        end
      end
    end
  end

  context "dedicated vm plan" do
    let(:redis_save_command) { "BGSAVE" }

    describe 'service backups', :skip_service_backups => true do
      let(:service) {
        Prof::MarketplaceService.new(
          name: bosh_manifest.property('redis.broker.service_name'),
          plan: 'dedicated-vm'
        )
      }

      describe 'manual snapshot' do
        let(:destination_folder) { bosh_manifest.property("service-backup.source_folder") }

        it 'creates a dump.rdb file' do
          service_broker.provision_and_bind(service.name, service.plan) do |service_binding, service_instance|
            vm_ip = service_binding.credentials[:host]
            result = ssh_gateway.execute_on(
              vm_ip,
              manual_snapshot_command
            )
            expect(result.lines.join).to(match('"event":"done","task":"create-snapshot"'), 'done event not found')

            ls_output = ssh_gateway.execute_on(
              vm_ip, "ls -l #{destination_folder}dump.rdb"
            )
            expect(ls_output.lines.size).to(eql(1))
            expect(ls_output.lines.first).to_not(match('No such file or directory'))
            expect(ls_output.lines.first).to(match("#{destination_folder}dump.rdb"))
          end
        end
      end

      describe 'manual backup' do
        before do
          instance_id = create_backup_for_service(service)

          @s3_backup_file = s3_client.buckets[s3_backup_bucket].objects.
            find_all {|object| object.key.include? "backup/#{Time.now.strftime("%Y/%m/%d")}"}.
            find { |object| "dump.rdb" }
        end

        after do
          @s3_backup_file.delete if @s3_backup_file
        end

        it 'uploads data to S3 in RDB format' do
          expect(@s3_backup_file.exists?).to eq(true)
          expect(@s3_backup_file.content_length).not_to eq(0)
          contents = @s3_backup_file.read

          # check RDB format
          expect(contents).to match(/^REDIS/)

          # check not AOF format
          expect(contents).to_not include('SELECT')
        end
      end

      describe 'manual cleanup' do
        it 'deletes the dump.rdb file' do
          service_broker.provision_and_bind(service.name, service.plan) do |service_binding, service_instance|
            vm_ip = service_binding.credentials[:host]
            result = ssh_gateway.execute_on(
              vm_ip,
              "touch #{destination_folder}/dump.rdb; ls #{destination_folder}"
            )
            expect(result.lines.join).to match("dump.rdb")

            cleanup_result = ssh_gateway.execute_on(
              vm_ip,
              manual_cleanup_command
            )
            expect(cleanup_result.lines.join).to match('"event":"done","task":"perform-cleanup"')

            ls_result = ssh_gateway.execute_on(
              vm_ip,
              "ls #{destination_folder}"
            )
            expect(ls_result.lines.join).to_not match("dump.rdb")
          end
        end
      end
    end
  end

  def create_backup_for_service(service)
    service_broker.provision_and_bind(service.name, service.plan) do |service_binding, service_instance|
      vm_ip = service_binding.credentials[:host]
      client = service_client_builder(service_binding)

      client.write(test_key, test_value)
      client.run(redis_save_command)

      with_redis_under_stress(service_binding) do
        result = ssh_gateway.execute_on(vm_ip, manual_backup_command)
        expect(result.lines.join).to(match(/Upload backup completed without error/))
      end

      return service_instance.id
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

    client = service_client_builder(service_binding)
    puts "Wrote #{client.info('used_memory_human')} of data to Redis"
  end
end
