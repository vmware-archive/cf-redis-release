module Helpers
  class ServiceInstance
    def initialize(id:)
      @id = id
    end

    attr_reader :id
  end
end
