require "logger"

require_relative "lib/bag_courier"
require_relative "lib/bag_tag"
require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/status_event"

LOGGER = Logger.new($stdout)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

work = BagCourier::Work.new(
  id: "00001",
  title: "Some title",
  creator: "Some creator",
  description: "Something something something"
)

bag_id = BagCourier::BagId.new(
  repository: config.repository_name,
  object_id: work.id,
  context: "some"
)

bag_info = BagTag::BagInfoBagTag.new(
  identifier: work.id,
  description: config.repository.description
)

aws_config = config.aptrust.aws
Remote::AwsS3Remote.update_config(aws_config.access_key_id, aws_config.secret_access_key)
aws_remote = Remote::AwsS3Remote.new(
  region: aws_config.region,
  bucket: aws_config.receiving_bucket
)

status_event_repo = StatusEvent::StatusEventInMemoryRepository.new

tags = [
  Aptrust::AptrustInfo.new(
    title: work.title,
    item_description: work.description,
    creator: work.creator
  )
]

courier = BagCourier::BagCourierService.new(
  bag_id: bag_id,
  bag_info: bag_info,
  tags: tags,
  remote: aws_remote,
  data_transfer: DataTransfer::DirDataTransfer.new(config.test_source_dir),
  status_event_repo: status_event_repo,
  working_dir: config.working_dir,
  export_dir: config.export_dir,
  dry_run: config.dry_run
)
courier.perform_deposit

LOGGER.info("Events")
status_event_repo.get_all_by_bag_id(bag_id.to_s).each do |e|
  LOGGER.info(e)
end
