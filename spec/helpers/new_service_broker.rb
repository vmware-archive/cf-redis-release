# frozen_string_literal: true
require 'helpers/new_service_broker_api'

module Helpers
  class NewServiceBroker

    def initialize(args = {})
      api_args = args.reject { |k, _v| k == :api }
      @api = args.fetch(:api) { Helpers::NewServiceBrokerApi.new(api_args) }
    end

    def provision_instance(service_name, plan_name)
      plan = service_plan(service_name, plan_name)
      api.provision_instance(plan)
    end

    def deprovision_instance(service_instance, service_name, plan_name)
      plan = service_plan(service_name, plan_name)
      api.deprovision_instance(service_instance, plan)
    end

    def bind_instance(service_instance, service_name, plan_name)
      plan = service_plan(service_name, plan_name)
      api.bind_instance(service_instance, plan)
    end

    def unbind_instance(service_instance, service_name, plan_name)
      plan = service_plan(service_name, plan_name)
      api.unbind_instance(service_instance, plan)
    end

    def service_plan(service_name, plan_name)
      api.catalog.service_plan(service_name, plan_name)
    end

    def debug
      api.debug
    end


    private
    attr_reader :api
  end
end