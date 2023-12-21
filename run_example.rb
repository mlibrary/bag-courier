require "logger"

require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"

LOGGER = Logger.new($stdout)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

dispatcher = Dispatcher::APTrustDispatcher.new(config.settings, config.repository, config.aptrust)

work = Dispatcher::Work.new(
  id: "00001",
  title: "Some title",
  creator: "Some creator",
  description: "Something something something"
)

courier = dispatcher.dispatch(
  work: work,
  data_transfer: DataTransfer::DirDataTransfer.new(config.test.work_source_dir),
  context: "somecontext"
)
courier.perform_deposit

LOGGER.info("Events")
courier.status_event_repo.get_all_by_bag_id(courier.bag_id.to_s).each do |e|
  LOGGER.info(e)
end
