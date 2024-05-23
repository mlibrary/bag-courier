require_relative "services"

config = S.config
DB = config.database && S.dbconnect

require_relative "lib/aptrust"
require_relative "lib/bag_repository"
require_relative "lib/bag_status"
require_relative "lib/status_event_repository"

class APTrustVerificationError < StandardError
end

class APTrustVerificationJob
  include DarkBlueLogger

  def initialize(config)
    aptrust_api = APTrust::APTrustAPI.from_config(
      base_url: config.aptrust.api.base_url,
      username: config.aptrust.api.username,
      api_key: config.aptrust.api.api_key
    )
    @bag_repo = BagRepository::BagRepositoryFactory.for(use_db: DB)
    @status_event_repo = S.status_event_repo
    @verifier = APTrust::APTrustVerifier.new(
      aptrust_api: aptrust_api, status_event_repo: @status_event_repo
    )
  end

  def process
    logger.info("Searching for bags with pending deposit verification")
    latest_events = @status_event_repo.get_latest_event_for_bags
    latest_deposited_events = latest_events.filter { |e| e.status == BagStatus::DEPOSITED }
    logger.info("Found #{latest_deposited_events.length} deposit(s) with pending verification")
    latest_deposited_events.each do |e|
      @verifier.verify(bag_identifier: e.bag_identifier, deposited_at: e.timestamp)
    end
  end
end

APTrustVerificationJob.new(config).process
