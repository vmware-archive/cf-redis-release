desc 'run all the specs'
task spec: %w(spec:system spec:unit)

desc 'Installs noaa'
task :install_noaa do
  `go get github.com/cloudfoundry/noaa/firehose_sample`
end

namespace :spec do
  require 'rspec/core/rake_task'

  task :system => :install_noaa

  desc 'run all of the system tests'
  RSpec::Core::RakeTask.new(:system) do |t|
    t.pattern = FileList['spec/system/**/*_spec.rb']
  end

  desc 'run all of the unit tests'
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = FileList['spec/unit/**/*_spec.rb']
  end
end

namespace :packages do
  desc 'list blobs'
  task :blobs do
    $LOAD_PATH.unshift(File.expand_path('src/london_blob_checker/lib'))
    require 'london_blob_checker/blob_config_scanner'
    packages = LondonBlobChecker::BlobConfigScanner.new('config/blobs.yml').packages
    packages.each do |p|
      puts "Package #{p.name}\t#{p.version}"
    end
  end
end

task default: :spec
