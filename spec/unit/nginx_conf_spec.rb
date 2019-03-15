require 'erb'

describe 'nginx conf templating' do

  let(:nginx_conf_template) {
    File.read(
        File.expand_path(
            '../../../jobs/cf-redis-broker/templates/nginx.conf.erb',
            __FILE__
        )
    )
  }

  def p(property_name)
    {
        'redis.broker.name' => 'cf@-redis!',
        'syslog_aggregator.address' => '127.0.0.0',
        'syslog_aggregator.port' => '1234'
    }.fetch(property_name, "")
  end

  def if_p(*property_names, &block)
    property_names.each do |property_name|
      return false if p(property_name) == ""
    end

    block.call
    true
  end

  def template_out_script
    ERB.new(nginx_conf_template).result(binding)
  end

  it 'strips out non-alphanumeric characters and replaces underscores with dashes' do
    conf = ""
    expect {
      conf = template_out_script
    }.to_not raise_error

    conf.lines.each do |line|
      if line.include?('BrokerNginxError') or line.include?('BrokerNginxAccess')
        expect(line).to include("Cf_redis")
      end
    end

  end

end
