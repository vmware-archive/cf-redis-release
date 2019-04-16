# frozen_string_literal: true
module Helpers
  class InstanceBinding
    attr_reader :id, :credentials, :service_instance

    def initialize(id:, credentials:, service_instance:)
      @id = id
      @credentials = credentials
      @service_instance = service_instance
    end

    def ==(other)
      is_a?(other.class) &&
        id == other.id &&
        credentials == other.credentials &&
        service_instance == other.service_instance
    end
  end
end