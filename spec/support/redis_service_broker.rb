require 'hula/service_broker/service_instance'

module Support
  class RedisServiceBroker
    def initialize(service_broker, service_name)
      @service_broker = service_broker
      @service_name = service_name
    end

    def service_instances
      clusters = service_broker.debug.fetch(:allocated).fetch(:clusters)
      (clusters || []).map { |service_instance|
        Hula::ServiceBroker::ServiceInstance.new(id: service_instance.fetch(:ID))
      }
    end

    def deprovision_service_instances!
      service_plan = service_broker.catalog.service_plan(service_name, "dedicated-vm")

      service_instances.each do |service_instance|
        puts "Found service instance #{service_instance.id.inspect}"
        service_broker.deprovision_instance(service_instance, service_plan)
      end
    end

    private

    attr_reader :service_broker, :service_name
  end
end
