require 'yaml'
require 'bosh/template/property_helper'

module BoshTemplateRenderContext
  extend Bosh::Template::PropertyHelper

  def self.build(job_name, manifest, links)
    context = self.merge_job_spec_defaults(job_name, manifest)
    context['links'] = links
    context
  end

  def self.merge_job_spec_defaults(job_name, manifest)
    global_properties = manifest.fetch('properties', {})

    jobs = manifest.fetch('instance_groups').first.fetch('jobs')
    job = jobs.find { |job| job.fetch('name') == job_name }
    job_properties = job.fetch('properties', {})

    job_properties.merge!(global_properties)

    job_spec = YAML.load_file("jobs/#{job_name}/spec")
    job_spec_properties = job_spec.fetch('properties')

    merged_properties = {}
    job_spec_properties.each_pair do |name, definition|
      self.copy_property(merged_properties, job_properties, name, definition['default'])
    end

    manifest.merge({'properties' => merged_properties})
  end
end
