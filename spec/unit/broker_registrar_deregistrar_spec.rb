require 'erb'

PROPERTIES = {
    "cf.api_url" => "http://api.my-cf.com",
    "cf.admin_username" => "admin",
    "cf.admin_password" => "password",
    "cf.admin_client" => "",
    "cf.admin_client_secret" => "",
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
    "redis.broker.dedicated_node_count" => 1,
    "redis.broker.enable_deprecate_dedicated_service_access" => false
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

shared_examples 'user or client can be configured' do
  context 'when user it configured' do
    let(:properties) {
      PROPERTIES.merge({
        "cf.admin_username" => "user",
        "cf.admin_password" => "password",
        "cf.admin_client" => "",
        "cf.admin_client_secret" => "",
      })
    }

    it 'does not skip ssl validation' do
      expect(template_out_script).to include("cf auth user password")
    end
  end

  context 'when user it configured' do
    let(:properties) {
      PROPERTIES.merge({
        "cf.admin_username" => "",
        "cf.admin_password" => "",
        "cf.admin_client" => "client",
        "cf.admin_client_secret" => "secret",
      })
    }

    it 'does not skip ssl validation' do
      expect(template_out_script).to include("cf auth client secret --client-credentials")
    end
  end

  context 'when neither user nor client is configured' do
    let(:properties) {
      PROPERTIES.merge({
        "cf.admin_username" => "",
        "cf.admin_password" => "",
        "cf.admin_client" => "",
        "cf.admin_client_secret" => "",
      })
    }

    it 'raises an error' do
      expect {
        template_out_script
      }.to raise_error("Either cf.admin_client and cf.admin_client credentials or cf.admin_username and cf.admin_password must be provided")
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

  it_behaves_like 'user or client can be configured'

  it 'does not raise an error' do
    expect {
      template_out_script
    }.to_not raise_error
  end

  context 'when no service orgs are provided' do
    it 'configures sevice access for all' do
      expect(template_out_script).to include("cf enable-service-access $BROKER_SERVICE_NAME")
    end
  end

  context 'when a single service org is provided' do
    let(:org_name) { "test-org" }
    let(:properties) {
      PROPERTIES.merge({
        "redis.broker.service_access_orgs" => [org_name]
      })
    }

    it 'configures sevice access for specified org' do
      expect(template_out_script).to include("cf enable-service-access -o #{org_name} $BROKER_SERVICE_NAME")
    end
  end

  context 'multiple services orgs are provided' do
    let(:org_1) { "test-org-1" }
    let(:org_2) { "test-org-2" }
    let(:properties) {
      PROPERTIES.merge({
        "redis.broker.service_access_orgs" => [org_1, org_2]
      })
    }

    it 'configures sevice access for specified orgs' do
      expect(template_out_script).to include("cf enable-service-access -o #{org_1} $BROKER_SERVICE_NAME")
      expect(template_out_script).to include("cf enable-service-access -o #{org_2} $BROKER_SERVICE_NAME")
    end
  end
  context 'when enable_deprecate_dedicated_service_access is true, dedicated service plan' do
    let(:properties){
      PROPERTIES.merge({
        "redis.broker.enable_deprecate_dedicated_service_access" => true
      })
    }

    it 'is disabled' do
      expect(template_out_script).to include("cf disable-service-access $BROKER_SERVICE_NAME -p dedicated-vm")
    end
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

  it_behaves_like 'user or client can be configured'
end

def p(property_name)
  properties.fetch(property_name)
end

def template_out_script
  ERB.new(broker_job_ctl_script).result(binding)
end
