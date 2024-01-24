require "logger"

require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"

LOGGER = Logger.new($stdout)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

target_client = Remote::RemoteFactory.from_config(
  type: config.remote.type,
  settings: config.remote.settings
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
  data_transfer: DataTransfer::DirDataTransfer.new(config.test.source_dir),
  context: "somecontext"
)
courier.deliver

LOGGER.info("Events")
courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
  LOGGER.info(e)
end
