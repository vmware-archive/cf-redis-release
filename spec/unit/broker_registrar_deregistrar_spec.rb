require 'erb'

PROPERTIES = {
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
    "redis.broker.enable_service_access" => true
}

shared_examples 'ssl validation is configurable' do
  context 'when ssl validation is enabled' do
    it 'does not skip ssl validation' do
      expect(template_out_script).to include("SKIP_SSL_VALIDATION=''")
      expect(template_out_script).to include("cf api $SKIP_SSL_VALIDATION $CF_API_URL")
    end
  end

  context 'when ssl validation is disabled' do
    let(:properties) {
      PROPERTIES.merge({
        "cf.skip_ssl_validation" => true
      })
    }

    it 'skips ssl validation' do
      expect(template_out_script).to include("SKIP_SSL_VALIDATION='--skip-ssl-validation'")
      expect(template_out_script).to include("cf api $SKIP_SSL_VALIDATION $CF_API_URL")
    end
  end
end

describe 'cf-redis-broker broker_registrar errand' do
  let(:properties) { PROPERTIES }

  let(:broker_job_ctl_script) {
    File.read(
      File.expand_path(
        '../../../jobs/broker-registrar/templates/errand.sh.erb',
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
end


describe 'cf-redis-broker broker_deregistrar errand' do
  let(:properties) { PROPERTIES }

  let(:broker_job_ctl_script) {
    File.read(
      File.expand_path(
        '../../../jobs/broker-deregistrar/templates/errand.sh.erb',
        __FILE__
      )
    )
  }

  it 'does not raise an error' do
    expect {
      template_out_script
    }.to_not raise_error
  end

  it_behaves_like 'ssl validation is configurable'
end

def p(property_name)
  properties.fetch(property_name)
end

def template_out_script
  ERB.new(broker_job_ctl_script).result(binding)
end
