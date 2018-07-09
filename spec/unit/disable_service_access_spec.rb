require 'erb'

SPEC_PROPERTIES = {
    "cf.api_url" => "http://api.my-cf.com",
    "cf.admin_username" => "admin",
    "cf.admin_password" => "password",
    "redis.broker.service_name" => "redis-service",
    "broker.name" => "dave",
    "broker.protocol" => "https",
    "broker.host" => "broker.com",
    "broker.username" => "user",
    "broker.password" => "password",
    "cf.skip_ssl_validation" => false,
    "redis.broker.enable_service_access" => true,
    "redis.broker.service_access_orgs" => [],
    "redis.broker.service_instance_limit" => 1,
    "redis.broker.dedicated_node_count" => 1
}

describe 'cf-redis-broker broker_registrar errand' do
  let(:properties) { SPEC_PROPERTIES }

  let(:broker_job_ctl_script) {
    File.read(
      File.expand_path(
        '../../../jobs/remove-deprecated-functionality/templates/errand.sh.erb',
        __FILE__
      )
    )
  }

  it_behaves_like 'ssl validation is configurable'

  it 'does not raise an error' do
    expect {
      template_out_script
    }.to_not raise_error
  end

  context 'dedicated service plan' do
    it 'is disabled' do
      expect(template_out_script).to include("cf disable-service-access $BROKER_SERVICE_NAME -p dedicated-vm")
    end
  end
end

def p(property_name)
  properties.fetch(property_name)
end

def template_out_script
  ERB.new(broker_job_ctl_script).result(binding)
end
