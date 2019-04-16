require 'helpers/service_instance'
require 'helpers/new_service_broker_api'

module Support
  class RedisServiceBroker
    def initialize(service_broker, service_name)
      @service_broker = service_broker
      @service_name = service_name
    end

    def service_instances
      clusters = service_broker.debug.fetch(:allocated).fetch(:clusters)
      (clusters || []).map { |service_instance|
        Helpers::ServiceInstance.new(id: service_instance.fetch(:ID))
      }
    end

    def deprovision_dedicated_service_instances!
      service_instances.each do |service_instance|
        puts "Found service instance #{service_instance.id.inspect}"
        service_broker.deprovision_instance(service_instance, service_name, "dedicated-vm")
      end
    end

    def deprovision_shared_service_instances!
      service_instances.each do |service_instance|
        puts "Found service instance #{service_instance.id.inspect}"
        service_broker.deprovision_instance(service_instance, service_name, "shared-vm")
      end
    end

    private

    attr_reader :service_broker, :service_name
  end
end
