require 'system_spec_helper'

describe 'metrics', :skip_metrics => true do
  before(:all) do
    @number_of_nodes = bosh_manifest.job(Helpers::Environment::DEDICATED_NODE_JOB_NAME).static_ips.count
    @origin_tag = bosh_manifest.property('service_metrics.origin')
    @outFile = Tempfile.new('smetrics')
    @pid = spawn(
      {
        "DOPPLER_ADDR" => doppler_address,
        "CF_ACCESS_TOKEN" => cf_auth_token
      },
      'firehose',
      [:out, :err] => [@outFile.path, 'w']
    )
  end

  after(:all) do
    Process.kill("INT", @pid)
    @outFile.unlink
  end

  describe 'broker metrics' do
    ["/p-redis/service-broker/dedicated_vm_plan/total_instances",
     "/p-redis/service-broker/dedicated_vm_plan/available_instances",
     "/p-redis/service-broker/shared_vm_plan/available_instances",
     "/p-redis/service-broker/shared_vm_plan/total_instances",
    ].each do |metric_name|
      it "contains #{metric_name} metric for redis broker" do
        assert_metric(metric_name, Helpers::Environment::BROKER_JOB_NAME, 0)
      end
    end
  end

  describe 'redis metrics' do
    ["/p-redis/info/cpu/used_cpu_sys",
     "/p-redis/info/memory/used_memory",
     "/p-redis/info/memory/maxmemory",
     "/p-redis/info/stats/total_commands_processed",
     "/p-redis/info/stats/total_connections_received",
     "/p-redis/info/memory/mem_fragmentation_ratio",
     "/p-redis/info/stats/evicted_keys",
     "/p-redis/info/server/uptime_in_seconds",
     "/p-redis/info/server/uptime_in_days",
    ].each do |metric_name|
      it "contains #{metric_name} metric for all dedicated nodes" do
        @number_of_nodes.times do |idx|
          assert_metric(metric_name, Helpers::Environment::DEDICATED_NODE_JOB_NAME, idx)
        end
      end
    end
  end

  def assert_metric(metric_name, job_name, job_index)
    metric = find_metric(metric_name, job_name, job_index)

    expect(metric).to match(/value:\d/)
    expect(metric).to include("origin:\"#{@origin_tag}\"")
    expect(metric).to include('deployment:"cf-redis"')
    expect(metric).to include('eventType:ValueMetric')
    expect(metric).to match(/timestamp:\d/)
    expect(metric).to match(/index:"[\dabcdef-]*"/)
    expect(metric).to match(/ip:"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"/)
  end

  def find_metric(metric_name, job_name, job_index)
    job_id = metron_id_from_job_index(job_name, job_index)
    60.times do
      File.open(firehose_out_file, "r") do |file|
        regex = /(?=.*job:"#{job_name}")(?=.*index:"#{job_id}")(?=.*name:"#{metric_name}")/
        matches = file.readlines.grep(regex)
        if matches.size > 0
          return matches[0]
        end
      end
      sleep 1
    end
    fail("metric '#{metric_name}' for job '#{job_name}' with index '#{job_id}' not found")
  end

  def metron_id_from_job_index(job_name, job_index)
    job_ssh = Helpers::BOSHCLIWrapper.new(bosh_manifest.deployment_name, job_name, job_index)

    metron_agent_config = job_ssh.execute('sudo cat /var/vcap/jobs/metron_agent/config/metron_agent.json')
    JSON.parse(metron_agent_config).fetch("Index")
  end

  def firehose_out_file
    @outFile.path
  end
end
