require "semantic_logger"

require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"
require_relative "lib/remote_client"

SemanticLogger.add_appender(io: $stderr, formatter: :color)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

SemanticLogger.default_level = config.settings.log_level
logger = SemanticLogger["run_example"]

target_client = RemoteClient::RemoteClientFactory.from_config(
  type: config.target_remote.type,
  settings: config.target_remote.settings
)

# Use a RemoteClient to move the object(s) to the source directory if it's in a remote
# location
# source_client = RemoteClient::RemoteClientFactory.from_config(
#   type: config.source_remote.type,
#   settings: config.source_remote.settings
# )
# source_client.retrieve_from_path(
#   remote_path: "some/remote/path",
#   local_path: config.settings.source_dir
# )

dispatcher = Dispatcher::APTrustDispatcher.new(
  settings: config.settings,
  repository: config.repository,
  target_client: target_client
)

object_metadata = Dispatcher::ObjectMetadata.new(
  id: "00001",
  title: "Some title",
  creator: "Some creator",
  description: "Something something something"
)

courier = dispatcher.dispatch(
  object_metadata: object_metadata,
  data_transfer: DataTransfer::DirDataTransfer.new(
    File.join(config.settings.source_dir, "some_directory")
  ),
  context: "somecontext"
)
courier.deliver

logger.info("Events")
courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
  logger.info(e)
end
