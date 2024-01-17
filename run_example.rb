require "logger"

require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"

LOGGER = Logger.new($stdout)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))

aws_config = config.aptrust.aws
Remote::AwsS3Remote.update_config(aws_config.access_key_id, aws_config.secret_access_key)
destination = Remote::AwsS3Remote.new(
  region: aws_config.region,
  bucket: aws_config.receiving_bucket
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
