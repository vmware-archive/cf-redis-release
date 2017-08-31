require 'bosh/template/renderer'
require 'helpers/bosh_template_render_context'

module Helpers
  module Utilities
    def render_template(template_path, job_name, manifest, links={})
      context = BoshTemplateRenderContext.build(job_name, manifest, links)
      renderer = Bosh::Template::Renderer.new(context: context.to_json)
      renderer.render(template_path)
    end

    def generate_manifest(minimum_manifest)
      manifest = YAML.load(minimum_manifest)
      yield(manifest) if block_given?
      manifest
    end
  end
end
