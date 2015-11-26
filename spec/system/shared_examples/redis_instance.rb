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
      it 'disables them if necesary' do
        service_broker.provision_and_bind(service.name, service.plan) do |binding|
          service_client = service_client_builder(binding)
          admin_command_availability.each do |command, available|
            if available
              expect { service_client.run(command) }.to_not raise_error
            else
              expect {
                service_client.run(command)
              }.to raise_error(/unknown command '#{command}'/)
            end
          end
        end
      end
    end

    context 'when redis related properties changed in the manifest' do
      before do
        bosh_manifest.set_property('redis.config_command', 'configalias')
        bosh_director.deploy
      end

      after do
        bosh_manifest.set_property('redis.config_command', 'configalias')
        bosh_director.deploy
      end

      it 'updates existing instances' do
        service_broker.provision_and_bind(service.name, service.plan) do |binding|
          redis_client_1 = service_client_builder(binding)
          redis_client_1.write('test', 'foobar')
          original_config_command = redis_client_1.config_command

          bosh_manifest.set_property('redis.config_command', 'newconfigalias')
          bosh_director.deploy

          redis_client_2 = service_client_builder(binding)
          new_config_command = redis_client_2.config_command
          expect(original_config_command).to_not eq(new_config_command)
          expect(redis_client_2.read('test')).to eq('foobar')
        end
      end
    end
  end
end
