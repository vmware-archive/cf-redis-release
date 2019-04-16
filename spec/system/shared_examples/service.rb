shared_examples_for 'a service that has distinct instances' do
  before(:all) do
    @service_instance = service_broker.provision_instance(service_name, service_plan_name)
    @service_binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
  end

  after(:all) do
    service_broker.unbind_instance(@service_binding, service_name, service_plan_name)
    service_broker.deprovision_instance(@service_instance, service_name, service_plan_name)
  end

  it 'has distinct instances' do
    service_client1 = service_client_builder(@service_binding)
    service_client1.write('test_key', 'test_value')

    service_instance2 = service_broker.provision_instance(service_name, service_plan_name)
    service_binding2 = service_broker.bind_instance(service_instance2, service_name, service_plan_name)

    service_client2 = service_client_builder(service_binding2)
    service_client2.write('test_key', 'another_test_value')
    expect(service_client1.read('test_key')).to eq('test_value')
    expect(service_client2.read('test_key')).to eq('another_test_value')

    service_broker.unbind_instance(service_binding2, service_name, service_plan_name)
    service_broker.deprovision_instance(service_instance2, service_name, service_plan_name)
  end
end

shared_examples_for 'a service that can be shared by multiple applications' do
  before(:all) do
    @service_instance = service_broker.provision_instance(service_name, service_plan_name)
    @service_binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
  end

  after(:all) do
    service_broker.unbind_instance(@service_binding, service_name, service_plan_name)
    service_broker.deprovision_instance(@service_instance, service_name, service_plan_name)
  end

  it 'allows two applications to share the same instance' do
    service_client1 = service_client_builder(@service_binding)
    service_client1.write('shared_test_key', 'test_value')
    expect(service_client1.read('shared_test_key')).to eq('test_value')

    service_binding2 = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
    service_client2 = service_client_builder(service_binding2)
    expect(service_client2.read('shared_test_key')).to eq('test_value')
    expect(service_client1.read('shared_test_key')).to eq('test_value')

    service_broker.unbind_instance(service_binding2, service_name, service_plan_name)
  end
end

shared_examples_for 'a service which preserves data across binding and unbinding' do
  it 'preserves data across binding and unbinding' do
    @service_instance = service_broker.provision_instance(service_name, service_plan_name)
    @service_binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
    service_client_builder(@service_binding).write('unbound_test_key', 'test_value')

    service_broker.unbind_instance(@service_binding,service_name, service_plan_name)
    @service_binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)

    expect(service_client_builder(@service_binding).read('unbound_test_key')).to eq('test_value')

    # this is not in an `after`-block, because the @service_binding gets re-assigned
    # once control exits the `it` block
    service_broker.unbind_instance(@service_binding,service_name, service_plan_name)
    service_broker.deprovision_instance(@service_instance, service_name, service_plan_name)
  end
end

shared_examples_for 'a service which preserves data when recreating the broker VM' do
  before(:all) do
    @service_instance = service_broker.provision_instance(service_name, service_plan_name)
    @service_binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
  end

  after(:all) do
    service_broker.unbind_instance(@service_binding,service_name, service_plan_name)
    service_broker.deprovision_instance(@service_instance, service_name, service_plan_name)
  end

  it 'preserves data when recreating vms' do
    service_client = service_client_builder(@service_binding)
    service_client.write('test_key', 'test_value')
    expect(service_client.read('test_key')).to eq('test_value')

    [environment.bosh_service_broker_job_name].each do |job_name|
      bosh.recreate(deployment_name, job_name)
    end

    expect(service_client.read('test_key')).to eq('test_value')
  end
end

shared_examples_for 'a persistent cloud foundry service' do
  describe 'a persistent cloud foundry service' do
    it_behaves_like 'a service that has distinct instances'
    it_behaves_like 'a service that can be shared by multiple applications'
    it_behaves_like 'a service which preserves data across binding and unbinding'
    it_behaves_like 'a service which preserves data when recreating the broker VM'
  end
end
