require "logger"

require_relative "bag_courier"
require_relative "config"
require_relative "data_transfer"
require_relative "status_event"

LOGGER = Logger.new($stdout)

config_data = Config::ConfigService.read_config_file(
  File.join(".", "config", "config.yml")
)
config = Config::ConfigService.create_config(config_data)

work = BagCourier::Work.new(
  id: "00001",
  title: "Some title",
  creator: "Some creator",
  description: "Something something something"
)

status_event_repo = StatusEvent::StatusEventInMemoryRepository.new

courier = BagCourier::BagCourierService.new(
  work: work,
  context: "some",
  config: config,
  data_transfer: DataTransfer::DirDataTransfer.new(config.test_source_dir),
  status_event_repo: status_event_repo
)

courier.perform_deposit

LOGGER.info("Events")
status_event_repo.get_all_by_work_id(work.id).each do |e|
  LOGGER.info(e)
end
