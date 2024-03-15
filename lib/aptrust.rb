require "faraday"
require "faraday/retry"
require "semantic_logger"

require_relative "api_backend"

module APTrust
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

    def initialize(api_backend:, api_prefix: API_V3, object_id_prefix: DEFAULT_OBJECT_ID_PREFIX)
      @backend = api_backend
      @api_prefix = api_prefix
      @object_id_prefix = object_id_prefix
    end

    def self.from_config(
      base_url:,
      username:,
      api_key:,
      api_backend: APIBackend::FaradayAPIBackend,
      api_prefix: API_V3,
      object_id_prefix: DEFAULT_OBJECT_ID_PREFIX
    )
      backend = api_backend.new(
        base_url: "#{base_url}#{api_prefix}",
        headers: {
          :accept => "application/json",
          :content_type => "application/json",
          "X-Pharos-API-User" => username,
          "X-Pharos-API-Key" => api_key
        }
      )
      new(api_backend: backend, api_prefix: api_prefix, object_id_prefix: object_id_prefix)
    end

    def get_ingest_status(bag_identifier)
      # This "Work Items" endpoint always returns multiple, paginated results. Hence `results.first` below.
      # See https://aptrust.github.io/registry/#/Work%20Items
      # We'll request one result per page, and use a "date desc" sort to get the most recently-processed ingest for this identifier.
      data = @backend.get("items", {
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

  class APTrustVerificationError < StandardError
  end

  class APTrustVerifier
    include SemanticLogger::Loggable

    def initialize(aptrust_api:, status_event_repo:)
      @aptrust_api = aptrust_api
      @status_event_repo = status_event_repo
    end

    def verify(bag_identifier)
      logger.info("Deposit with pending verification found for bag #{bag_identifier}.")
      status = @aptrust_api.get_ingest_status(bag_identifier)
      logger.debug("Ingest status from APTrust: #{status}")
      case status
      when APTrust::IngestStatus::SUCCESS
        @status_event_repo.create(
          bag_identifier: bag_identifier,
          status: "deposit_verified",
          timestamp: Time.now.utc,
          note: "Ingest to APTrust verified"
        )
        logger.info("Deposit for bag #{bag_identifier} was verified.")
      when APTrust::IngestStatus::FAILED, APTrust::IngestStatus::CANCELLED
        @status_event_repo.create(
          bag_identifier: bag_identifier,
          status: "deposit_failed",
          timestamp: Time.now.utc,
          note: "Ingest to APTrust failed with status \"#{status}\""
        )
        logger.error("Deposit for bag #{bag_identifier} failed.")
      when APTrust::IngestStatus::NOT_FOUND
        raise APTrustVerificationError, "No record of deposit for #{bag_identifier} found"
      when APTrust::IngestStatus::PROCESSING
        logger.info("Deposit for #{bag_identifier} is still being processed.")
      end
    end
  end
end
