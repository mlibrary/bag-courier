require "logger"

require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"

LOGGER = Logger.new($stdout)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

destination = Remote::RemoteFactory.from_config(
  type: config.remote.type,
  settings: config.remote.settings
)

dispatcher = Dispatcher::APTrustDispatcher.new(
  settings: config.settings,
  repository: config.repository,
  destination: destination
)

courier = dispatcher.dispatch(
  work: work,
  data_transfer: DataTransfer::DirDataTransfer.new(config.test.work_source_dir),
  context: "somecontext"
)
courier.deliver

LOGGER.info("Events")
courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
  LOGGER.info(e)
end
