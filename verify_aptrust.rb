require "semantic_logger"
require "sequel"

require_relative "lib/config"

SemanticLogger.add_appender(io: $stderr, formatter: :color)
config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))
SemanticLogger.default_level = config.settings.log_level

DB = config.database && Sequel.connect(
  adapter: "mysql2",
  host: config.database.host,
  port: config.database.port,
  database: config.database.database,
  user: config.database.user,
  password: config.database.password,
  fractional_seconds: true
)

require_relative "lib/aptrust"
require_relative "lib/bag_repository"
require_relative "lib/status_event_repository"

class APTrustVerificationError < StandardError
end

class APTrustVerificationJob
  include SemanticLogger::Loggable

  def initialize(config)
    @aptrust_api = APTrust::APTrustAPI.from_config(
      base_url: config.aptrust_api.base_url,
      username: config.aptrust_api.username,
      api_key: config.aptrust_api.api_key
    )
    @bag_repo = BagRepository::BagRepositoryFactory.for(use_db: DB)
    @status_event_repo = StatusEventRepository::StatusEventRepositoryFactory.for(use_db: DB)
  end

  def process
    @bag_repo.get_all.each do |bag|
      logger.debug(bag)
      latest_event = @status_event_repo.get_latest_event_for_bag(bag_identifier: bag.identifier)
      logger.debug(latest_event)
      next if latest_event&.status != "deposited"

      logger.info("Deposit with pending verification found.")
      status = @aptrust_api.get_ingest_status(bag.identifier)
      logger.debug("Ingest status from APTrust: #{status}")
      case status
      when APTrust::IngestStatus::SUCCESS
        @status_event_repo.create(
          bag_identifier: bag.identifier,
          status: "deposit_verified",
          timestamp: Time.now.utc,
          note: "Ingest to APTrust verified"
        )
      when APTrust::IngestStatus::FAILED, APTrust::IngestStatus::CANCELLED
        @status_event_repo.create(
          bag_identifier: bag.identifier,
          status: "deposit_failed",
          timestamp: Time.now.utc,
          note: "Ingest to APTrust failed with status \"#{status}\""
        )
      when APTrust::IngestStatus::NOT_FOUND
        raise APTrustVerificationError, "No record of deposit for #{bag.identifier} found"
      when APTrust::IngestStatus::PROCESSING
        logger.debug("Deposit for #{bag.identifier} is still being processed.")
      end
    end
  end
end

APTrustVerificationJob.new(config).process
