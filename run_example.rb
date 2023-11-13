require_relative "bag_courier"
require_relative "config"
require_relative "data_transfer"

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

courier = BagCourier::BagCourierService.new(
  work: work,
  config: config,
  data_transfer: DataTransfer::DirDataTransfer.new(config.test_source_dir),
  context: "some"
)

courier.perform_deposit
