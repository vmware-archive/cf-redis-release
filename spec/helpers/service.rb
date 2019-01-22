module Helpers

  class Service
    def initialize(name:, plan:)
      @name = name
      @plan = plan
    end

    attr_reader :name, :plan
  end

end