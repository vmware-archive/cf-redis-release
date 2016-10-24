def root_execute_on(ip, command)
  root_prompt = '[sudo] password for vcap: '
  root_prompt_length = root_prompt.length

  output = ssh_gateway.execute_on(ip, command, root: true)
  expect(output).not_to be_nil
  expect(output).to start_with(root_prompt)
  return output.slice(root_prompt_length, output.length - root_prompt_length)
end

def log_is_earlier?(log_line, timestamp)
  match = log_line.scan( /\{.*\}$/ ).first

  return true if match.nil?

  begin
    json_log = JSON.parse(match)
  rescue JSON::ParserError
    return true
  end

  log_timestamp = json_log["timestamp"].to_i
  log_timestamp < timestamp.to_i
end

def drop_log_lines_before(time, log_lines)
  log_lines.lines.drop_while do |log_line|
    log_is_earlier?(log_line, @preprovision_timestamp)
  end
end

def wait_for_process_start(process_name, vm_ip)
  for _ in 0..18 do
    puts "Waiting for #{process_name} to start"
    sleep 5
    return true if process_running?(process_name, vm_ip)
  end

  puts "Process #{process_name} did not start within 90 seconds"
  return false
end

def process_running?(process_name, vm_ip)
  monit_output = root_execute_on(vm_ip, "/var/vcap/bosh/bin/monit summary | grep #{process_name} | grep running")
  !monit_output.strip.empty?
end
