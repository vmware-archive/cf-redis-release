module Helpers
  module Utilities
    def drop_log_lines_before(time, log_lines)
      log_lines.lines.drop_while do |log_line|
        log_is_earlier?(log_line, time)
      end
    end

    private

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
  end
end
