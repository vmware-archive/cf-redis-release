require 'yaml'
require 'bosh/template/renderer'
require 'tempfile'
require 'fileutils'

describe 'errands spec' do
  let(:temp_log_dir) { Dir.mktmpdir('temp_log_dir') }
  # let(:manifest) { YAML.load_file('spec/fixtures/cf-redis.yml') }
  let(:manifest) {
    {
      "properties" => {
        "cf" => {
          "admin_username" => "admin",
          "admin_password" => "adminpassword",
          "api_url" => "http://api.bosh-lite.com",
          "skip_ssl_validation" => true
        },
        "redis" => {
          "broker" => {
            "service_name" => "p-redis-broker",
            "enable_service_access" => true,
            "service_access_orgs" => [],
            "service_instance_limit" => 1,
            "dedicated_node_count" => 1
          }
        },
        "broker" => {
          "name" => "p-redis",
          "protocol" => "https",
          "host" => "redis-broker.bosh-lite.com",
          "username" => "brokeradmin",
          "password" => "brokerpassword"
        }
      }
    }
  }
  let(:broker_properties) { {protocol: 'https', port: 443} }
  let(:renderer) { Bosh::Template::Renderer.new({context: manifest.to_json}) }

  let(:rendered_template_file) {
    rendered_template = renderer.render('jobs/broker-registrar/templates/errand.sh.erb')

    rendered_template_file = Tempfile.new('rendered_template')
    rendered_template_file.write(rendered_template)
    rendered_template_file.close

    return rendered_template_file
  }

  after do
      FileUtils.rm_rf temp_log_dir
  end

  describe 'broker-registrar' do
    before do
      manifest['properties']['broker'].merge!(broker_properties)
    end

    describe 'when SKIP_SSL_VALIDATION is true' do
      it 'skips certificate verification if configured to do so' do
        manifest['properties']['cf'].merge!({skip_ssl_validation: true})

        expect(File.read(rendered_template_file)).to include("SKIP_SSL_VALIDATION='--skip-ssl-validation'")
      end
    end

    describe 'when SKIP_SSL_VALIDATION is false' do
      it 'does not skip certificate verification' do
        manifest['properties']['cf'].merge!({skip_ssl_validation: false})

        expect(File.read(rendered_template_file)).to include("SKIP_SSL_VALIDATION=''")
      end
    end
  end
end
