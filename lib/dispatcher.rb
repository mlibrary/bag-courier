require_relative "bag_courier"
require_relative "bag_tag"
require_relative "data_transfer"
require_relative "remote"

LOGGER = Logger.new($stdout)

module Dispatcher
  Work = Struct.new("Work", :id, :creator, :description, :title)

  class DispatcherBase
    def dispatch(work:, data_transfer:, context: nil)
      raise NotImplementedError
    end
  end

  class APTrustDispatcher < DispatcherBase
    attr_reader :status_event_repo

    def initialize(config)
      @config = config

      aws_config = config.aptrust.aws
      LOGGER.debug(aws_config)
      Remote::AwsS3Remote.update_config(aws_config.access_key_id, aws_config.secret_access_key)
      @remote = Remote::AwsS3Remote.new(
        region: aws_config.region,
        bucket: aws_config.receiving_bucket
      )

      @status_event_repo = StatusEvent::StatusEventInMemoryRepository.new
    end

    def dispatch(work:, data_transfer:, context: nil)
      bag_id = BagCourier::BagId.new(
        repository: @config.repository.name,
        object_id: work.id,
        context: context
      )
      bag_info = BagTag::BagInfoBagTag.new(
        identifier: work.id,
        description: @config.repository.description
      )
      tags = [
        BagTag::AptrustInfoBagTag.new(
          title: work.title,
          item_description: work.description,
          creator: work.creator
        )
      ]

      BagCourier::BagCourier.new(
        bag_id: bag_id,
        bag_info: bag_info,
        tags: tags,
        remote: @remote,
        data_transfer: data_transfer,
        status_event_repo: @status_event_repo,
        working_dir: @config.working_dir,
        export_dir: @config.export_dir,
        dry_run: @config.dry_run
      )
    end
  end
end
