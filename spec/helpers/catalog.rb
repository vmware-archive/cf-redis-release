# frozen_string_literal: true

require 'helpers/service'

module Helpers
  class Catalog
    attr_reader :services

    def initialize(args = {})
      @services = args.fetch(:services).map { |s| Helpers::Service.new(s) }
    end

    def ==(other)
      is_a?(other.class) &&
        services == other.services
    end

    def service(service_name)
      service = services.find { |s| s.name == service_name }

      if service.nil?
        raise(ServiceNotFoundError,
              %(Unknown service with name: #{service_name.inspect}) +
                  "\n Known service names: #{services.map(&:name).inspect}")
      end
      service
    end

    def service_plan(service_name, plan_name)
      service(service_name).plan(plan_name)
    end
  end
end