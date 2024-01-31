require_relative "bag_courier"
require_relative "bag_tag"
require_relative "data_transfer"
require_relative "remote"
require_relative "status_event"

module Dispatcher
  ObjectMetadata = Struct.new(
    "ObjectMetadata",
    :id,
    :creator,
    :description,
    :title,
    keyword_init: true
  )

  class DispatcherBase
    def dispatch(object_metadata:, data_transfer:, context: nil)
      raise NotImplementedError
    end
  end

  class APTrustDispatcher < DispatcherBase
    attr_reader :status_event_repo

    def initialize(
      settings:,
      repository:,
      destination:,
      status_event_repo: StatusEvent::StatusEventInMemoryRepository.new
    )
      @settings = settings
      @repository = repository
      @destination = destination
      @status_event_repo = status_event_repo
    end

    def dispatch(object_metadata:, data_transfer:, context: nil)
      bag_id = BagCourier::BagId.new(
        repository: @repository.name,
        object_id: object_metadata.id,
        context: context
      )
      bag_info = BagTag::BagInfoBagTag.new(
        identifier: object_metadata.id,
        description: @repository.description
      )
      tags = [
        BagTag::AptrustInfoBagTag.new(
          title: object_metadata.title,
          item_description: object_metadata.description,
          creator: object_metadata.creator
        )
      ]

      BagCourier::BagCourier.new(
        bag_id: bag_id,
        bag_info: bag_info,
        tags: tags,
        destination: @destination,
        data_transfer: data_transfer,
        status_event_repo: @status_event_repo,
        working_dir: @settings.working_dir,
        export_dir: @settings.export_dir,
        dry_run: @settings.dry_run
      )
    end
  end
end
