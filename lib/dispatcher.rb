require_relative "bag_courier"
require_relative "bag_repository"
require_relative "bag_tag"
require_relative "data_transfer"
require_relative "status_event_repository"

module Dispatcher
  class DispatcherBase
    def dispatch(bag_id:, object_metadata:, data_transfer:, context: nil)
      raise NotImplementedError
    end
  end

  class APTrustDispatcher < DispatcherBase
    attr_reader :status_event_repo, :bag_repo

    def initialize(
      settings:,
      repository:,
      target_client:,
      status_event_repo: StatusEventRepository::StatusEventInMemoryRepository.new,
      bag_repo: BagRepository::BagInMemoryRepository.new
    )
      @settings = settings
      @repository = repository
      @target_client = target_client
      @status_event_repo = status_event_repo
      @bag_repo = bag_repo
    end

    def dispatch(bag_id:, object_metadata:, data_transfer:, context: nil)
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

      @bag_repo.create(identifier: bag_id.to_s, group_part: bag_id.part_id || 1)

      BagCourier::BagCourier.new(
        bag_id: bag_id,
        bag_info: bag_info,
        tags: tags,
        target_client: @target_client,
        data_transfer: data_transfer,
        status_event_repo: @status_event_repo,
        working_dir: @settings.working_dir,
        export_dir: @settings.export_dir,
        dry_run: @settings.dry_run
      )
    end
  end
end
