require 'yaml'

require 'london_blob_checker/package'

module LondonBlobChecker
  class BlobConfigScanner
    def initialize(yml_path)
      @yml_path = yml_path
    end

    def packages
      yaml.map { |filepath, _details| Package.new(filepath) }
    end

    private

    attr_reader :yml_path

    def yaml
      @yaml ||= YAML.load_file(yml_path)
    end
  end
end
