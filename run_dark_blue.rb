require "logger"

require_relative "lib/archivematica"
require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"

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
  id = File.basename(package.path).gsub("-" + package.uuid, "")
  LOGGER.info("Object ID/Title: #{id}")

  # Copy file to local source directory, using SFTP or shared mount
  source_client.retrieve_files(
    remote_path: package.path,
    local_path: config.test.work_source_dir
  )
  # Extract metadata if possible?
  # context = nil # maybe some way to determine what content type?
  # object_metadata = Dispatcher::ObjectMetadata.new(
  #   id: id,
  #   creator: "Not available",
  #   description: "Not available",
  #   title: id
  # )
  # Dispatch courier and deliver
  # courier = dispatcher.dispatch(
  #   object_metadata: object_metadata,
  #   data_transfer: DataTransfer::DirDataTransfer.new(some_local_path),
  #   context: context
  # )
  # courier.deliver
end

# LOGGER.info("Events")
# courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
#   LOGGER.info(e)
# end
