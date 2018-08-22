require 'erb'

CLEANUP_SPEC_PROPERTIES = {
    "cf.api_url" => "http://api.my-cf.com",
    "cf.admin_username" => "admin",
    "cf.admin_password" => "password",
    "cf.skip_ssl_validation" => false,
    "redis.broker.dedicated_node_count" => 0,
    "redis.broker.dedicated_vm_plan_id" => "dedicated_vm_plan_id",
}

describe 'cf-redis-broker broker_registrar errand' do
  let(:properties) { CLEANUP_SPEC_PROPERTIES }

  let(:broker_job_ctl_script) {
    File.read(
      File.expand_path(
        '../../../jobs/cleanup-metadata-if-dedicated-disabled/templates/errand.sh.erb',
        __FILE__
      )
    )
  }

  it 'does not raise an error' do
    expect {
      template_out_script
    }.to_not raise_error
  end

  context 'dedicated service plan' do
    it 'is checked for service instances in Cloud Controller' do
      expect(template_out_script).to include("cf curl /v2/service_plans?q=unique_id:${DEDICATED_VM_PLAN_ID}")
    end
  end
end

def p(property_name)
  properties.fetch(property_name)
end

def template_out_script
  ERB.new(broker_job_ctl_script).result(binding)
end
