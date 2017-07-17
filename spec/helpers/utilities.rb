require 'net/http'
require 'uri'
require 'timeout'

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

    def get_line_from_gosyslogd_endpoint(syslog_endpoint)
      uri = URI(syslog_endpoint)
      Net::HTTP.get(uri).strip
    end

    def drain_gosyslogd_endpoint(syslog_endpoint)
      ten_milliseconds = 0.01
      five_minutes = 60 * 5

      Timeout::timeout(five_minutes) {
        while true do
          if get_line_from_gosyslogd_endpoint(syslog_endpoint).include? 'no logs available' then
            return
          end

          sleep ten_milliseconds
        end
      }
    end
  end
end
