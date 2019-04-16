
module Helpers

  class Error < StandardError; end

  class NotInCatalog < Error; end
  class PlanNotFoundError < NotInCatalog; end
  class ServiceNotFoundError < NotInCatalog; end

  class JsonParseError < Error; end
  class TimeoutError < Error; end
  class HTTPError < Error; end

  class HttpProxyNull
    def http_host
      nil
    end
    def http_port
      nil
    end
  end

  class NewHttpJsonClient
    def initialize(http_proxy: HttpProxyNull.new)
      @http_proxy = http_proxy
    end

    def get(uri, auth: nil, headers: nil)
      request = Net::HTTP::Get.new(uri)
      request.basic_auth auth.fetch(:username), auth.fetch(:password) unless auth.nil?

      headers&.each do |key, value|
        request.add_field(key, value)
      end

      send_request(request)
    end

    def put(uri, body: nil, auth: nil, headers: nil)
      request = Net::HTTP::Put.new(uri)
      request.body = JSON.generate(body) if body
      request.basic_auth auth.fetch(:username), auth.fetch(:password) unless auth.nil?
      headers&.each do |key, value|
        request.add_field(key, value)
      end
      send_request(request)
    end

    def delete(uri, auth: nil, headers: nil, params: nil)
      request = Net::HTTP::Delete.new(uri)
      request.basic_auth auth.fetch(:username), auth.fetch(:password) unless auth.nil?
      headers&.each do |key, value|
        request.add_field(key, value)
      end
      send_request(request)
    end

    private

    attr_reader :http_proxy

    def send_request(request)
      uri = request.uri
      make_request(uri.hostname, uri.port, uri.scheme, request)
    end

    def make_request(host, port, scheme, request)
      response = Net::HTTP.start(
          host,
          port,
          http_proxy.http_host,
          http_proxy.http_port,
          use_ssl: scheme == 'https',
          verify_mode: OpenSSL::SSL::VERIFY_NONE
      ) { |http| http.request(request) }

      handle(response)
    rescue Timeout::Error => e
      raise TimeoutError, e
    end

    def handle(response)
      unless response.is_a?(Net::HTTPSuccess)
        raise HTTPError, [
            response.uri.to_s,
            response.code,
            response.body
        ].join("\n\n")
      end

      JSON.parse(response.body, symbolize_names: true)
    rescue JSON::ParserError => e
      raise JsonParseError, e
    end
  end
end