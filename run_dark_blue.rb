require "semantic_logger"

require_relative "lib/archivematica"
require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"
require_relative "lib/remote_client"

SemanticLogger.add_appender(io: $stdout, formatter: :color)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

SemanticLogger.default_level = config.settings.log_level
logger = SemanticLogger["run_dark_blue"]

dark_blue_api = Archivematica::ArchivematicaAPI.from_config(
  base_url: config.archivematica.base_url,
  api_key: config.archivematica.api_key,
  username: config.archivematica.username
)

packages = dark_blue_api.get_packages(
  location_uuid: config.archivematica.location_uuid
)

source_client = RemoteClient::RemoteClientFactory.from_config(
  type: config.source_remote.type,
  settings: config.source_remote.settings
)

target_client = RemoteClient::RemoteClientFactory.from_config(
  type: config.target_remote.type,
  settings: config.target_remote.settings
)

dispatcher = Dispatcher::APTrustDispatcher.new(
  settings: config.settings,
  repository: config.repository,
  target_client: target_client
)

selected_packages = packages.select { |p| p.size < config.settings.object_size_limit }
logger.info("Number of packages below object size limit: #{selected_packages.length}")

selected_packages.each do |package|
  logger.info(package)
  inner_bag_dir_name = File.basename(package.path)
  logger.info("Inner bag name: #{inner_bag_dir_name}")
  ingest_dir_name = inner_bag_dir_name.gsub("-" + package.uuid, "")
  logger.info("Directory name on Archivematica ingest: #{ingest_dir_name}")

  # Copy file to local source directory, using SFTP or shared mount
  source_client.retrieve_from_path(
    remote_path: package.path,
    local_path: config.settings.source_dir
  )
  # Extract metadata if possible?
  # context = nil # maybe some way to determine what content type?
  object_metadata = Dispatcher::ObjectMetadata.new(
    id: package.uuid,
    creator: "Not available",
    description: "Not available",
    title: "#{package.uuid} / #{ingest_dir_name}"
  )

  # Dispatch courier and deliver
  inner_bag_source_path = File.join(config.settings.source_dir, inner_bag_dir_name)
  courier = dispatcher.dispatch(
    object_metadata: object_metadata,
    data_transfer: DataTransfer::DirDataTransfer.new(inner_bag_source_path)
    # context: nil
  )
  courier.deliver
  logger.info("Events")
  courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
    logger.info(e)
  end
end
