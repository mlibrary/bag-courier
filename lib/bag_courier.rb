require "minitar"
require "tty-command"

require_relative "bag_adapter"
require_relative "bag_status"
require_relative "remote_client"
require_relative "../services"

module BagCourier
  class TarFileCreator
    def self.create(src_dir_path:, dest_file_path:, verbose: false)
      src_parent = File.dirname(src_dir_path)
      src_dir = File.basename(src_dir_path)
      flags = "-cf#{verbose ? "v" : ""}"
      TTY::Command.new.run("tar", flags, dest_file_path, "--directory=#{src_parent}", src_dir)
    end
  end

  class BagId
    attr_reader :repository, :object_id, :context, :part_id

    def initialize(repository:, object_id:, context: nil, part_id: nil)
      @repository = repository
      @context = context
      @object_id = object_id
      @part_id = part_id
    end

    def to_s
      segments = [@context, @object_id, @part_id].select { |segment| !segment.nil? }
      "#{@repository}.#{segments.join "-"}"
    end
  end

  class BagCourier
    include DarkBlueLogger

    EXT_TAR = ".tar"

    attr_reader :bag_id, :status_event_repo

    def initialize(
      bag_id:,
      bag_info:,
      tags:,
      data_transfer:,
      target_client:,
      working_dir:,
      export_dir:,
      remove_export:,
      dry_run:,
      status_event_repo:,
      validator:
    )
      @bag_id = bag_id
      @bag_info = bag_info
      @tags = tags

      @data_transfer = data_transfer
      @target_client = target_client
      @status_event_repo = status_event_repo

      @working_dir = working_dir
      @export_dir = export_dir
      @remove_export = remove_export
      @dry_run = dry_run
      @validator = validator
    end

    def track!(status:, note: nil)
      @status_event_repo.create(
        bag_identifier: @bag_id.to_s,
        status: status,
        timestamp: Time.now.utc,
        note: note
      )
    end

    def create_tar(target_path:, output_dir_path:)
      logger.debug([
        "target_path=#{target_path}",
        "output_dir_path=#{output_dir_path}",
        "bag_id=#{@bag_id}"
      ])

      tar_src = File.basename(target_path)
      tar_file = tar_src + EXT_TAR
      new_path = File.join(output_dir_path, tar_file)

      track!(status: BagStatus::PACKING)
      TarFileCreator.create(src_dir_path: target_path, dest_file_path: new_path)
      track!(status: BagStatus::PACKED)
      new_path
    end

    def deposit(file_path:)
      logger.debug(["file_path=#{file_path}", "bag_id=#{@bag_id}"])

      logger.debug("dry_run=#{@dry_run}")
      if @dry_run
        track!(status: BagStatus::DEPOSIT_SKIPPED)
        return
      end

      logger.info("Sending bag to #{@target_client.remote_text}")
      # add timing
      track!(status: BagStatus::DEPOSITING)
      @target_client.send_file(local_file_path: file_path)
      track!(status: BagStatus::DEPOSITED)
    end

    def deliver
      logger.debug("bag_id=#{@bag_id}")

      begin
        track!(status: BagStatus::BAGGING)
        bag_path = File.join(@working_dir, @bag_id.to_s)
        bag = BagAdapter::BagAdapter.new(bag_path)

        track!(status: BagStatus::COPYING)
        @data_transfer.transfer(bag.data_dir)
        track!(status: BagStatus::COPIED)

        if @validator
          track!(status: BagStatus::VALIDATING)
          @validator.validate(bag.data_dir)
          track!(status: BagStatus::VALIDATED)
        else
          track!(status: BagStatus::VALIDATION_SKIPPED)
        end

        @tags.each do |tag|
          bag.add_tag_file!(
            tag_file_text: tag.serialize,
            file_name: tag.file_name
          )
        end
        bag.add_bag_info(@bag_info.data)
        bag.add_manifests
        track!(status: BagStatus::BAGGED, note: "bag_path: #{bag_path}")

        export_tar_file_path = create_tar(
          target_path: bag.bag_dir, output_dir_path: @export_dir
        )
        logger.debug("export_tar_file_path=#{export_tar_file_path}")

        FileUtils.rm_r(bag.bag_dir)
        deposit(file_path: export_tar_file_path)
        FileUtils.rm(export_tar_file_path) if @remove_export
      rescue => e
        note = "failed with error #{e.class}: #{e.full_message}"
        track!(status: BagStatus::FAILED, note: note)
        logger.error("BagCourier.deliver #{note}")
      end
    end
  end
end
