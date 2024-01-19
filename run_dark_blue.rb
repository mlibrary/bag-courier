require "logger"

require_relative "lib/archivematica"
require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"

LOGGER = Logger.new($stdout)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))
LOGGER.info(config)

dark_blue_api = Archivematica::ArchivematicaAPI.new(
  base_url: config.archivematica.base_url,
  api_key: config.archivematica.api_key,
  username: config.archivematica.username
)

packages = dark_blue_api.get_packages(config.archivematica.location_uuid)

destination = Remote::RemoteFactory.from_config(
  type: config.remote.type,
  settings: config.remote.settings
)

dispatcher = Dispatcher::APTrustDispatcher.new(
  settings: config.settings,
  repository: config.repository,
  destination: destination
)

packages.each do |package|
  LOGGER.info(package)
  id = File.basename(package.path).gsub("-" + package.uuid, "")
  LOGGER.info("Object ID/Title: #{id}")
  # Copy file to local source directory here, using SFTP or shared mount?
  # Extract metadata if possible?
  # context = nil # maybe some way to determine what content type?
  # work = Dispatcher::Work.new(
  #   id: id,
  #   creator: "Unknown",
  #   description: "Unknown",
  #   title: id
  # )
  # Dispatch courier and deliver
  # courier = dispatcher.dispatch(
  #   work: work,
  #   data_transfer: DataTransfer::DirDataTransfer.new(some_local_path),
  #   context: context
  # )
  # courier.deliver
end

# LOGGER.info("Events")
# courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
#   LOGGER.info(e)
# end
