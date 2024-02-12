require "logger"

require_relative "lib/archivematica"
require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"
require_relative "lib/remote_client"

KB = 1000
MB = KB * 1000
GB = MB * 1000

LOGGER = Logger.new($stdout)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

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

SIZE_LIMIT = GB * 2
packages.select { |p| p.size < SIZE_LIMIT }.each do |package|
  LOGGER.info(package)
  inner_bag_dir_name = File.basename(package.path)
  LOGGER.info("Inner bag name: #{inner_bag_dir_name}")
  ingest_dir_name = inner_bag_dir_name.gsub("-" + package.uuid, "")
  LOGGER.info("Directory name on Archivematica ingest: #{ingest_dir_name}")

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
  LOGGER.info("Events")
  courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
    LOGGER.info(e)
  end
end
