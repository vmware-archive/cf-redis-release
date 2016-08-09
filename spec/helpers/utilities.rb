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
