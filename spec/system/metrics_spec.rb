require 'system_spec_helper'

describe 'metrics' do
  before(:all) do
    @outFile = Tempfile.new('smetrics')
    @pid = spawn(
      {
        "DOPPLER_ADDR" => doppler_address,
        "CF_ACCESS_TOKEN" => cf_auth_token
      },
      'firehose_sample',
      [:out, :err] => [@outFile.path, 'w']
    )
  end

  after(:all) do
    Process.kill("INT", @pid)
    @outFile.unlink
  end

  describe 'broker metrics' do
    ["/redis/broker/dedicated_vm_plan/total_instances",
     "/redis/broker/dedicated_vm_plan/available_instances"
    ].each do |metric_name|
      it "contains #{metric_name} metric for redis broker" do
        assert_metric(metric_name, 'cf-redis-broker', 0)
      end
    end
  end

  describe 'redis metrics' do
    ["/redis/info/cpu/used_cpu_sys",
     "/redis/info/memory/used_memory",
     "/redis/info/stats/total_commands_processed",
     "/redis/info/stats/total_connections_received",
     "/redis/info/memory/mem_fragmentation_ratio",
     "/redis/info/stats/evicted_keys",
     "/redis/info/cpu/used_cpu_sys",
     "/redis/info/server/uptime_in_seconds",
     "/redis/info/server/uptime_in_days"
    ].each do |metric_name|
      5.times do |idx|
        it "contains #{metric_name} metric for dedicated node #{idx}" do
          assert_metric(metric_name, 'dedicated-node', idx)
        end
      end
    end
  end

  def assert_metric(metric_name, job_name, job_index)
    metric = find_metric(metric_name, job_name, job_index)

    expect(metric).to match(/value:\d/)
    expect(metric).to include('origin:"p-redis"')
    expect(metric).to include('deployment:"cf-redis"')
    expect(metric).to include('eventType:ValueMetric')
    expect(metric).to match(/timestamp:\d/)
    expect(metric).to match(/index:"\d"/)
    expect(metric).to match(/ip:"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"/)
  end

  def find_metric(metric_name, job_name, job_index)
    60.times do
      File.open(firehose_out_file, "r") do |file|
        regex = /(?=.*name:"#{metric_name}")(?=.*job:"#{job_name}")(?=.*index:"#{job_index}")/
        matches = file.readlines.grep(regex)
        if matches.size > 0
          return matches[0]
        end
      end
      sleep 1
    end
    fail("metric '#{metric_name}' for job '#{job_name}' with index '#{job_index}' not found")
  end

  def firehose_out_file
    @outFile.path
  end
end
