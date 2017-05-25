require 'system_spec_helper'

require 'aws-sdk'

require 'prof/marketplace_service'

describe 'backups', :run_backup_spec => true do

  let(:redis_config_command) { bosh_manifest.property("redis.config_command") }
  let(:broker_vm_ip) { bosh_director.ips_for_job('cf-redis-broker', bosh_manifest.deployment_name).first }

  let(:s3_client) { Aws::S3::Client.new }
  let(:s3_backup_bucket) { bosh_manifest.property("redis.broker.backups.bucket_name") }

  let(:test_key) { "test_key" }
  let(:test_value) { "test_value" }

  context "shared vm plan" do
    let(:redis_save_command) { bosh_manifest.property("redis.save_command") }

    it "sets a crontab entry on the broker" do
      expected = [
        "0 0 * * *",
        "PATH=$PATH:/var/vcap/packages/aws-cli/bin",
        "/var/vcap/packages/cf-redis-broker/bin/backup",
        "--config",
        "/var/vcap/jobs/cf-redis-broker/config/backup.yml"
      ].join(" ")
      crontab_output = ssh_gateway.execute_on(
        broker_vm_ip, "crontab -l -u vcap", root: true, discard_stderr: true
      )

      expect(crontab_output).not_to be_nil
      crontab_output = crontab_output.to_s.split("\n")

      expect(crontab_output).to include(expected)
    end

    describe 'manual backup on the shared-vm plan' do
      let(:service) {
        Prof::MarketplaceService.new(
          name: bosh_manifest.property('redis.broker.service_name'),
          plan: 'shared-vm'
        )
      }

      before do
        instance_id = create_backup_for_service(service)

        s3_backup_file_meta = s3_client.list_objects(bucket: s3_backup_bucket).contents.
          find_all { |object| object.key.include? "backups/#{Time.now.strftime("%Y/%m/%d")}" }.
          find { |object| object.key.include?(instance_id) }

        unless s3_backup_file_meta.nil?
          @s3_backup_file = s3_client.get_object(bucket: s3_backup_bucket, key: s3_backup_file_meta.key).body
        end
      end

      after do
        Aws::S3::Bucket.new(name: s3_backup_bucket, client: s3_client).clear!
      end

      it 'uploads data to S3 in RDB format' do
        expect(@s3_backup_file).not_to be_nil
        expect(@s3_backup_file.size).to be > 0
        contents = @s3_backup_file.read.encode('UTF-8', 'UTF-8', :invalid => :replace)

        # check RDB format
        expect(contents).to match(/^REDIS/)

        # check not AOF format
        expect(contents).to_not include('SELECT')
      end

      it 'restores the data from an S3 file' do
        expect(@s3_backup_file).not_to be_nil
        tempfile = Tempfile.new('backup.rdb', :encoding => @s3_backup_file.external_encoding.name)
        tempfile.write(@s3_backup_file.read)
        tempfile.close

        service_broker.provision_and_bind(service.name, service.plan) do |service_binding, service_instance|
          remote_path = "/home/vcap/backup.rdb"

          ssh_gateway.scp_to(broker_vm_ip, tempfile.path, remote_path)

          restore_command = "/var/vcap/packages/cf-redis-broker/bin/restore #{service_instance.id} #{remote_path}; echo $?"
          restore_output = ssh_gateway.execute_on(broker_vm_ip, restore_command, root: true)
          expect(restore_output).not_to be_nil
          expect(restore_output.lines.last.strip).to(eql('0'), 'restore command failed with non zero exit status')

          wait_until_redis_is_up(broker_vm_ip)

          client = service_client_builder(service_binding)
          expect(client.read(test_key)).to eq(test_value)
        end
      end
    end
  end

  context "dedicated vm plan" do
    let(:redis_save_command) { "BGSAVE" }

    it "sets a crontab entry on the broker" do
      first_dedicated_node_vm_ip = bosh_director.ips_for_job('dedicated-node', bosh_manifest.deployment_name).first

      expected = [
        "0 0 * * *",
        "PATH=$PATH:/var/vcap/packages/aws-cli/bin",
        "/var/vcap/packages/cf-redis-broker/bin/backup",
        "--config",
        "/var/vcap/jobs/dedicated-node/config/backup.yml"
      ].join(" ")
      crontab_output = ssh_gateway.execute_on(
        first_dedicated_node_vm_ip, "crontab -l -u vcap", root: true, discard_stderr: true
      ).to_s.split("\n")

      expect(crontab_output).to include(expected)
    end

    describe 'manual backup' do
      let(:service) {
        Prof::MarketplaceService.new(
          name: bosh_manifest.property('redis.broker.service_name'),
          plan: 'dedicated-vm'
        )
      }

      before do
        instance_id = create_backup_for_service(service)

        s3_backup_file_meta = s3_client.list_objects(bucket: s3_backup_bucket).contents.
          find_all { |object| object.key.include? "backups/#{Time.now.strftime("%Y/%m/%d")}" }.
          find { |object| object.key.include?(instance_id) }

        unless s3_backup_file_meta.nil?
          @s3_backup_file = s3_client.get_object(bucket: s3_backup_bucket, key: s3_backup_file_meta.key).body
        end
      end

      after do
        Aws::S3::Bucket.new(name: s3_backup_bucket, client: s3_client).clear!
      end

      it 'uploads data to S3 in RDB format' do
        expect(@s3_backup_file).not_to be_nil
        expect(@s3_backup_file.size).to be > 0
        contents = @s3_backup_file.read.encode('UTF-8', 'UTF-8', :invalid => :replace)

        # check RDB format
        expect(contents).to match(/^REDIS/)

        # check not AOF format
        expect(contents).to_not include('SELECT')
      end

      it 'restores the data from an S3 file' do
        expect(@s3_backup_file).not_to be_nil
        tempfile = Tempfile.new('backup.rdb', :encoding => @s3_backup_file.external_encoding.name)
        tempfile.write(@s3_backup_file.read)
        tempfile.close

        service_broker.provision_and_bind(service.name, service.plan) do |service_binding, service_instance|
          remote_path = "/home/vcap/backup.rdb"

          dedicated_node_vm_ip = service_binding.credentials[:host]

          ssh_gateway.scp_to(dedicated_node_vm_ip, tempfile.path, remote_path)

          restore_command = "RESTORE_CONFIG_PATH=/var/vcap/jobs/dedicated-node/config/restore.yml /var/vcap/packages/cf-redis-broker/bin/restore #{service_instance.id} #{remote_path}; echo $?"
          restore_output = ssh_gateway.execute_on(dedicated_node_vm_ip, restore_command, root: true)
          expect(restore_output).not_to be_nil
          expect(restore_output.lines.last.strip).to(eql('0'), "restore command failed with non zero exit status, output was:\n#{restore_output}")

          wait_until_redis_is_up(dedicated_node_vm_ip)

          client = service_client_builder(service_binding)
          expect(client.read(test_key)).to eq(test_value)
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
        result = ssh_gateway.execute_on(vm_ip, backup_command_from_crontab(vm_ip))
        expect(result.lines.last.strip).to(eql('0'), 'backup command failed with non zero exit status')
      end

      return service_instance.id
    end
  end

  def backup_command_from_crontab(vm_ip)
    crontab_output = ssh_gateway.execute_on(
      vm_ip, "crontab -l -u vcap", root: true, discard_stderr: true
    ).to_s.split("\n")

    backup_command = crontab_output.find do |cron_command|
      cron_command.include?("--config")
    end
    backup_command.gsub!("0 0 * * * ", "")
    backup_command += "; echo $?"
  end

  def wait_until_redis_is_up(host)
    redis_up = false
    counter = 0
    until redis_up do
      output = ssh_gateway.execute_on(host, "ps aux | grep [r]edis-server", root: true, discard_stderr: true)
      redis_up = (output =~ /redis\-server/)
      sleep 1 # deliberately sleep even after we know redis process is up to allow it time to initialize
      counter += 1
      break if counter >= 30
    end
    expect(counter < 30).to be(true), "Redis did not come back up within 30 seconds."
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
