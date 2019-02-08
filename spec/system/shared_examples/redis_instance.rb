shared_examples_for 'a redis instance' do
  describe 'redis configuration' do
    it 'persists instance data in both RBD and AOF formats' do
      service_broker.provision_and_bind(service.name, service.plan) do |binding|
        service_client = service_client_builder(binding)
        rdb_config = service_client.config.fetch('save')
        expect(rdb_config).to eq('900 1 300 10 60 10000')

        rdb_config = service_client.config.fetch('appendonly')
        expect(rdb_config).to eq('yes')
      end
    end

    describe 'redis admin commands' do
      it 'disables them if necessary' do
        service_broker.provision_and_bind(service.name, service.plan) do |binding|
          service_client = service_client_builder(binding)
          admin_command_availability.each do |command, available|
            if available
              expect { service_client.run(command) }.to_not raise_error
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
end
