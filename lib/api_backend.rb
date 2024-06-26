require "faraday"
require "faraday/retry"

module APIBackend
  class APIError < StandardError
    attr_reader :status

    def initialize(message:, status:)
      super(message)
      @status = status
    end
  end

  module ResponseStatus
    RESOURCE_NOT_FOUND = 404
  end

  class APIBackendBase
    def get
      raise NotImplementedError
    end
  end

  class FaradayAPIBackend < APIBackendBase
    def initialize(base_url:, headers:, &b)
      @base_url = base_url
      @conn = Faraday.new(url: base_url, headers: headers) do |builder|
        builder.request :retry
        builder.response :raise_error
        b&.call(builder)
      end
    end

    def get(url:, params: nil)
      resp = @conn.get(url, params)
      JSON.parse(resp.body)
    rescue Faraday::Error => error
      message = "Error occurred while interacting with REST API at #{@base_url}. " \
        "Error type: #{error.class}; " \
        "status code: #{error.response_status || "none"}; " \
        "body: #{error.response_body || "none"}"
      raise APIError.new(message: message, status: error.response_status)
    end
  end
end
