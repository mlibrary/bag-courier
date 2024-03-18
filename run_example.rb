require "semantic_logger"

require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"
require_relative "lib/remote_client"

SemanticLogger.add_appender(io: $stderr, formatter: :color)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

SemanticLogger.default_level = config.settings.log_level
logger = SemanticLogger["run_example"]

# Build your target client here; APTrust is the standard target and specified here.
target_client = RemoteClient::RemoteClientFactory.from_config(
  type: config.aptrust.remote.type,
  settings: config.aptrust.remote.settings
)

# A RemoteClient will be used to copy your object into the bag
source_client = RemoteClient::RemoteClientFactory.from_config(
  type: :file_system,
  settings: Config::FileSystemRemoteConfig.new(
    remote_path: "some/source/path/for/object"
  )
)

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
  data_transfer: DataTransfer::RemoteClientDataTransfer.new(
    source_client
    # remote_path: # use this if your object isn't at the root of the remote
  ),
  context: "somecontext"
)
courier.deliver

logger.info("Events")
courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
  logger.info(e)
end
