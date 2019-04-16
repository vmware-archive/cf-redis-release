shared_examples_for 'a redis instance' do
  before(:all) do
    @service_instance = service_broker.provision_instance(service_name, service_plan_name)
    @service_binding = service_broker.bind_instance(@service_instance, service_name, service_plan_name)
  end

  after(:all) do
    service_plan = service_broker.service_plan(service_name, service_plan_name)
    service_broker.unbind_instance(@service_binding, service_plan)
    service_broker.deprovision_instance(@service_instance, service_plan)
  end

  describe 'redis configuration' do
    it 'persists instance data in both RBD and AOF formats' do
      service_client = service_client_builder(@service_binding)
      rdb_config = service_client.config.fetch('save')
      expect(rdb_config).to eq('900 1 300 10 60 10000')

      rdb_config = service_client.config.fetch('appendonly')
      expect(rdb_config).to eq('yes')
    end

    describe 'redis admin commands' do
      it 'disables them if necessary' do
        service_client = service_client_builder(@service_binding)
        admin_command_availability.each do |command, available|
          if available
            expect {service_client.run(command)}.to_not raise_error
          else
            expect {
              service_client.run(command)
            }.to raise_error(/unknown command `#{command}`/)
          end
        end
      end
    end
  end
end
