require_relative "bag_courier"
require_relative "bag_repository"
require_relative "bag_tag"
require_relative "data_transfer"
require_relative "status_event_repository"

module Dispatcher
  class DispatcherBase
    def dispatch(
      object_metadata:,
      data_transfer:,
      validator: nil
    )
      raise NotImplementedError
    end
  end

  class APTrustDispatcher < DispatcherBase
    attr_reader :status_event_repo, :bag_repo

    def initialize(
      settings:,
      repository:,
      target_client:,
      context: nil,
      extra_bag_info_data: nil,
      detect_hidden: true,
      status_event_repo: StatusEventRepository::StatusEventInMemoryRepository.new,
      bag_repo: BagRepository::BagInMemoryRepository.new
    )
      @settings = settings
      @repository = repository
      @context = context
      @extra_bag_info_data = extra_bag_info_data
      @target_client = target_client
      @status_event_repo = status_event_repo
      @bag_repo = bag_repo
      @detect_hidden = detect_hidden
    end

    def dispatch(
      object_metadata:,
      data_transfer:,
      validator: nil
    )
      bag_id = BagCourier::BagId.new(
        repository: @repository.name,
        object_id: object_metadata.id,
        context: @context
      )
      bag_info = BagTag::BagInfoBagTag.new(
        identifier: object_metadata.id,
        description: @repository.description,
        extra_data: @extra_bag_info_data
      )
      tags = [
        BagTag::AptrustInfoBagTag.new(
          title: object_metadata.title,
          item_description: object_metadata.description,
          creator: object_metadata.creator,
          storage_option: BagTag::AptrustInfoBagTag::StorageOption::GLACIER_DEEP_OR
        )
      ]

      @bag_repo.create(
        identifier: bag_id.to_s,
        group_part: bag_id.part_id || 1,
        repository_package_identifier: bag_id.object_id
      )

      BagCourier::BagCourier.new(
        bag_id: bag_id,
        bag_info: bag_info,
        tags: tags,
        data_transfer: data_transfer,
        validator: validator,
        detect_hidden: @detect_hidden,
        target_client: @target_client,
        status_event_repo: @status_event_repo,
        working_dir: @settings.working_dir,
        export_dir: @settings.export_dir,
        dry_run: @settings.dry_run,
        remove_export: @settings.remove_export
      )
    end
  end
end
