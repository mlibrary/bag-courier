require "faraday"
require "faraday/retry"
require "semantic_logger"

module APTrust
  class APTrustAPIError < StandardError
  end

  module IngestStatus
    CANCELLED = "cancelled"
    FAILED = "failed"
    NOT_FOUND = "not found"
    PROCESSING = "processing"
    SUCCESS = "success"
  end

  class APTrustAPI
    include SemanticLogger::Loggable

    API_V3 = "/member-api/v3/"
    DEFAULT_OBJECT_ID_PREFIX = "umich.edu/"

    def initialize(conn, api_prefix: API_V3, object_id_prefix: DEFAULT_OBJECT_ID_PREFIX)
      @conn = conn
      @api_prefix = api_prefix
      @object_id_prefix = object_id_prefix
    end

    def self.from_config(
      base_url:,
      username:,
      api_key:,
      api_prefix: API_V3,
      object_id_prefix: DEFAULT_OBJECT_ID_PREFIX
    )
      conn = Faraday.new(
        url: "#{base_url}#{api_prefix}",
        headers: {
          :accept => "application/json",
          :content_type => "application/json",
          "X-Pharos-API-User" => username,
          "X-Pharos-API-Key" => api_key
        }
      ) do |builder|
        builder.request :retry
        builder.response :raise_error
      end
      new(conn, api_prefix: api_prefix)
    end

    def get(url, params = nil)
      resp = @conn.get(url, params)
      JSON.parse(resp.body)
    rescue Faraday::Error => error
      message = "Error occurred while interacting with APTrust API. " \
        "Error type: #{error.class}; " \
        "status code: #{error.response_status || "none"}; " \
        "body: #{error.response_body || "none"}"
      raise APTrustAPIError, message
    end

    def get_ingest_status(bag_identifier)
      # This "Work Items" endpoint always returns multiple, paginated results. Hence `results.first` below.
      # See https://aptrust.github.io/registry/#/Work%20Items
      # We'll request one result per page, and use a "date desc" sort to get the most recently-processed ingest for this identifier.
      data = get("items", {
        object_identifier: @object_id_prefix + bag_identifier,
        action: "Ingest",
        per_page: 1,
        sort: "date_processed__desc"
      })
      return IngestStatus::NOT_FOUND if data["results"].size == 0
      first_result = data["results"][0]
      status = first_result["status"]
      stage = first_result["stage"]
      logger.debug(status)
      logger.debug(stage)

      if /failed/i.match?(status)
        IngestStatus::FAILED
      elsif /cancelled/i.match?(status)
        IngestStatus::CANCELLED
      elsif /success/i.match?(status) && /cleanup/i.match?(stage)
        IngestStatus::SUCCESS
      else
        IngestStatus::PROCESSING
      end
    end
  end
end
