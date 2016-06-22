require 'erb'

describe 'cf-redis-broker job control script templating' do

  let(:broker_job_ctl_script) {
    File.read(
      File.expand_path(
        '../../../jobs/cf-redis-broker/templates/cf-redis-broker_ctl.erb',
        __FILE__
      )
    )
  }

  def p(property_name)
    {
      'redis.log_directory' => '/var/vcap/stuff/logs',
      'redis.data_directory' => '/var/vcap/stuff/redis_data',
      'redis.statefile_path' => '/var/vcap/stuff/my_file',
      'syslog_aggregator.address' => '10.0.0.1',
      'syslog_aggregator.port' => '9999',
      'redis.broker.backend_port' => '9875',
      'redis.broker.backups.endpoint_url' => endpoint_url,
      'redis.broker.backups.bucket_name' => bucket_name,
      'redis.broker.backups.backup_tmp_dir' => 'some/backup/tmp/dir',
      'redis.broker.backups.restore_available' => true,
    }.fetch(property_name, "")
  end

  def if_p(*property_names)
    property_names.each do |property_name|
      return false if p(property_name) == ""
    end
    true
  end

  def template_out_script
    ERB.new(broker_job_ctl_script).result(binding)
  end

  context 'when both the s3 endpoint and bucket name properties are set' do
    let(:endpoint_url) { 'some_url' }
    let(:bucket_name) { 'bucket_name' }

    it 'does not raise' do
      expect {
        template_out_script
      }.to_not raise_error
    end
  end

  context 'when neither the s3 endpoint nor bucket name properties are set' do
    let(:endpoint_url) { '' }
    let(:bucket_name) { '' }

    it 'does not raise' do
      expect {
        template_out_script
      }.to_not raise_error
    end
  end

  context 'when the s3 endpoint but not the bucket name property is set' do
    let(:endpoint_url) { 'some_url' }
    let(:bucket_name) { '' }

    it 'does not raise' do
      expect {
        template_out_script
      }.to_not raise_error
    end
  end

  context 'when the bucket name but not the s3 endpoint property is set' do
    let(:endpoint_url) { '' }
    let(:bucket_name) { 'bucket' }

    it 'does not raise' do
      expect {
        template_out_script
      }.to_not raise_error
    end
  end

end
