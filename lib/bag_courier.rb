require "minitar"
require "semantic_logger"

require_relative "bag_adapter"
require_relative "remote_client"

module BagCourier
  class BagCourier
    include SemanticLogger::Loggable

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
      dry_run:,
      status_event_repo:
    )
      @bag_id = bag_id
      @bag_info = bag_info
      @tags = tags

      @data_transfer = data_transfer
      @target_client = target_client
      @status_event_repo = status_event_repo

      @working_dir = working_dir
      @export_dir = export_dir
      @dry_run = dry_run
    end

    def track!(status:, note: nil)
      @status_event_repo.create(
        bag_identifier: @bag_id.to_s,
        status: status,
        timestamp: Time.now.utc,
        note: note
      )
    end

    def tar(target_path)
      logger.debug(["target_path=#{target_path}", "bag_id=#{@bag_id}"])

      parent = File.dirname target_path
      Dir.chdir(parent) do
        tar_src = File.basename target_path
        tar_file = File.basename(target_path) + EXT_TAR
        logger.debug([
          "target_path=#{target_path}",
          "parent=#{parent}",
          "tar_src=#{tar_src}",
          "tar_file=#{tar_file}"
        ])
        track!(status: "packing")
        Minitar.pack(tar_src, File.open(tar_file, "wb"))
        track!(status: "packed")
      end
      new_path = target_path + EXT_TAR
      logger.debug([
        "target_path=#{target_path}",
        "bag_id=#{@bag_id}",
        "new_path=#{new_path}"
      ])
      new_path
    end

    def deposit(file_path:)
      logger.debug(["file_path=#{file_path}", "bag_id=#{@bag_id}"])

      bag_sent = false
      logger.debug("dry_run=#{@dry_run}")
      if @dry_run
        track!(status: "deposit_skipped")
        return bag_sent
      end

      logger.info("Sending bag to #{@target_client.remote_text}")
      begin
        # add timing
        track!(status: "depositing")
        @target_client.send_file(local_file_path: file_path)
        track!(status: "deposited")
      rescue RemoteClient::RemoteClientError => e
        track!(status: "failed", note: "failed in #{e.context} with error #{e}")
        logger.error(
          ["Sending of file #{filename} failed in #{e.context} with error #{e}"] +
          e.backtrace[0..20]
        )
      end
    end

    def deliver
      logger.debug("bag_id=#{@bag_id}")

      begin
        track!(status: "bagging")
        bag_path = File.join(@working_dir, @bag_id.to_s)
        bag = BagAdapter::BagAdapter.new(bag_path)

        track!(status: "copying")
        @data_transfer.transfer(bag.data_dir)
        track!(status: "copied")

        @tags.each do |tag|
          bag.add_tag_file!(
            tag_file_text: tag.serialize,
            file_name: tag.file_name
          )
        end
        bag.add_bag_info(@bag_info.data)
        bag.add_manifests
        track!(status: "bagged", note: "bag_path: #{bag_path}")

        tar_file_path = tar(bag.bag_dir)
        export_tar_file_path = File.join(@export_dir, File.basename(tar_file_path))
        logger.debug([
          "export_dir=#{@export_dir}",
          "tar_file_path=#{tar_file_path}",
          "export_tar_file_path=#{export_tar_file_path}"
        ])
        FileUtils.mv(tar_file_path, export_tar_file_path)
        FileUtils.rm_r(bag.bag_dir)

        deposit(file_path: export_tar_file_path)
      rescue => e
        logger.error(
          ["BagCourier.deliver error: #{e}"] + e.backtrace[0..20]
        )
      end
    end
  end
end
