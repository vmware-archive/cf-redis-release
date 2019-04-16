# frozen_string_literal: true
module Helpers
  class Plan
    def initialize(args = {})
      @id = args.fetch(:id)
      @name = args.fetch(:name)
      @description = args.fetch(:description)
      @service_id = args.fetch(:service_id)
    end

    attr_reader :id, :name, :description, :service_id

    def ==(other)
      is_a?(other.class) &&
        id == other.id &&
        name == other.name &&
        description == other.description &&
        service_id == other.service_id
    end
  end
end