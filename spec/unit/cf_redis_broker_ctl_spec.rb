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
    }.fetch(property_name)
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

  it 'does not raise' do
    expect {
      template_out_script
    }.to_not raise_error
  end

end
