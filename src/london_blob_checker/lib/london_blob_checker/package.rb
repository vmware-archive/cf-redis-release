module LondonBlobChecker
  class Package
    def initialize(path)
      @path = path
    end

    def filename
      File.basename(path)
    end

    def name
      /[a-z]([a-z\d]*[a-z])?/.match(filename)[0]
    end

    def version
      /^(\d+(\.\d+)*)(-p\d+)?/.match(version_platform).to_a.first
    end

    def format
      @format ||= begin
        f = /(\.[a-z][a-z\d]*){1,2}$/.match(filename).to_a.first
        return if f.nil?
        f.sub(/^\./, '')
      end
    end

    def platform
      @platform ||= begin
        p = strip(
          version_platform.sub(Regexp.new("^#{Regexp.escape(version)}"), '')
        )
        return nil if p == ''
        p
      end
    end

    private

    attr_reader :path

    def version_platform
      strip(
        filename
          .sub(Regexp.new("^#{Regexp.escape(name)}"), '')
          .sub(Regexp.new("#{Regexp.escape(format)}$"), '')
      )
    end

    def strip(string)
      string
        .sub(/^[\-\.]/, '')
        .sub(/[\-\.]$/, '')
    end
  end
end
