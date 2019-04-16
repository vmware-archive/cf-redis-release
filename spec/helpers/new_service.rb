# frozen_string_literal: true

require 'helpers/plan'

module Helpers
  class NewService
    def initialize(args = {})
      @id          = args.fetch(:id)
      @name        = args.fetch(:name)
      @description = args.fetch(:description)
      @bindable    = !!args.fetch(:bindable)
      @plans       = args.fetch(:plans).map { |p| Plan.new(p.merge(service_id: id)) }
    end

    attr_reader :id, :name, :description, :bindable, :plans

    def ==(other)
      is_a?(other.class) &&
        id == other.id &&
        name == other.name &&
        description == other.description &&
        bindable == other.bindable &&
        plans == other.plans
    end

    def plan(plan_name)
      plans.find { |p| p.name == plan_name } ||
        raise(PlanNotFoundError, [
          %(Unknown plan with name: #{plan_name.inspect}),
          "  Known plan names are: #{plans.map(&:name).inspect}"
        ].join("\n"))
    end
  end
end
