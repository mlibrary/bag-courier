require_relative "bag_courier"
require_relative "bag_tag"
require_relative "data_transfer"
require_relative "remote"
require_relative "status_event"

module Dispatcher
  Work = Struct.new("Work", :id, :creator, :description, :title)

  class DispatcherBase
    def dispatch(work:, data_transfer:, context: nil)
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

    def dispatch(work:, data_transfer:, context: nil)
      bag_id = BagCourier::BagId.new(
        repository: @repository.name,
        object_id: work.id,
        context: context
      )
      bag_info = BagTag::BagInfoBagTag.new(
        identifier: work.id,
        description: @repository.description
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
