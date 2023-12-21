require "logger"

require "minitar"

require_relative "bag_adapter"
require_relative "remote"
require_relative "status_event"

LOGGER = Logger.new($stdout)

module BagCourier
  Work = Struct.new("Work", :id, :creator, :description, :title)

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

  class BagCourierService
    EXT_TAR = ".tar"

    attr_reader :bag_id, :status_history

    def initialize(
      bag_id:,
      bag_info:,
      tags:,
      data_transfer:,
      remote:,
      status_event_repo:,
      working_dir:,
      export_dir:,
      dry_run:
    )
      @bag_id = bag_id
      @bag_info = bag_info
      @tags = tags

      @data_transfer = data_transfer
      @remote = remote
      @status_event_repo = status_event_repo

      @working_dir = working_dir
      @export_dir = export_dir
      @dry_run = dry_run
    end

    def track!(status:, note: nil)
      status_event = {bag_id: @bag_id.to_s, object_id: @bag_id.object_id, status: status, timestamp: Time.now}
      if !note.nil?
        status_event[:note] = note
      end
      @status_event_repo.create(status_event)
    end

    def tar(target_path)
      LOGGER.debug(["target_path=#{target_path}", "bag_id=#{@bag_id}"])

      parent = File.dirname target_path
      Dir.chdir(parent) do
        tar_src = File.basename target_path
        tar_file = File.basename(target_path) + EXT_TAR
        LOGGER.debug([
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
      LOGGER.debug([
        "target_path=#{target_path}",
        "bag_id=#{@bag_id}",
        "new_path=#{new_path}"
      ])
      new_path
    end

    def deposit(file_path:)
      LOGGER.debug([
        "file_path=#{file_path}",
        "bag_id=#{@bag_id}"
      ])

      deposited = false
      LOGGER.debug("dry_run=#{@dry_run}")
      if @dry_run
        track!(status: "deposit_skipped")
        return deposited
      end

      begin
        # add timing
        track!(status: "uploading")
        @remote.upload_file(file_path)
        deposited = true
        track!(status: "uploaded")
      rescue Remote::RemoteError => e
        track!(status: "failed", note: "failed in #{e.context} with error #{e}")
        LOGGER.error(
          ["Upload of file #{filename} failed in #{e.context} with error #{e}"] +
          e.backtrace[0..20]
        )
      end
      deposited
    end

    def perform_deposit
      LOGGER.debug("bag_id=#{@bag_id}")

      begin
        track!(status: "depositing")
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
        LOGGER.debug([
          "export_dir=#{@export_dir}",
          "tar_file_path=#{tar_file_path}",
          "export_tar_file_path=#{export_tar_file_path}"
        ])
        FileUtils.mv(tar_file_path, export_tar_file_path)
        FileUtils.rm_r(bag.bag_dir)

        deposited = deposit(file_path: export_tar_file_path)
        track!(status: "deposited") if deposited
      rescue => e
        LOGGER.error(
          ["BagCourierService.perform_deposit error: #{e}"] + e.backtrace[0..20]
        )
        track!(status: "failed", note: "failed with error #{e}")
      end
    end
  end
end
