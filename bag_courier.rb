require "logger"

require "bagit"
require "minitar"

require_relative "aptrust_info"
require_relative "status_event"

LOGGER = Logger.new($stdout)

module BagCourier
  Work = Struct.new("Work", :id, :creator, :description, :title)

  class BagAdapter
    def initialize(target_dir)
      @bag = BagIt::Bag.new(target_dir)
      @additional_tag_files = []
    end

    def bag_dir
      @bag.bag_dir
    end

    def data_dir
      @bag.data_dir
    end

    def add_bag_info(bag_info_data)
      @bag.write_bag_info(bag_info_data)
    end

    def add_tag_file!(tag_file_text:, file_name:)
      file = File.join(@bag.bag_dir, file_name)
      File.write(file, tag_file_text, mode: "w")
      @additional_tag_files << file
    end

    def add_manifests
      LOGGER.debug([
        "bag.tag_files=#{@bag.tag_files}",
        "additional_tag_files=#{@additional_tag_files}"
      ])
      @bag.manifest!(algo: "md5") # Create manifests

      # Rewrite the tag manifest files to include extra tag files
      tag_files = @bag.tag_files
      new_tag_files = tag_files & @additional_tag_files
      LOGGER.debug("new_tag_files=#{new_tag_files}")
      @bag.tagmanifest!(new_tag_files) unless (new_tag_files - tag_files).empty?

      # HELIO-4380 demo.aptrust.org doesn't like this file for some reason, gives an ingest error:
      # "Bag contains illegal tag manifest 'sha1'""
      # APTrust only wants SHA256, or MD5, not SHA1.
      # 'tagmanifest-sha1.txt' is a bagit gem default, so we need to remove it manually.
      sha1tag = File.join(@bag.bag_dir, "tagmanifest-sha1.txt")
      File.delete(sha1tag) if File.exist?(sha1tag)
    end
  end

  class BagCourierService
    @@allow_deposit = false

    IDENTIFIER_TEMPLATE = "%repository%.%context%.%id%"
    BAG_INFO_KEY_SOURCE = "Source-Organization"
    BAG_INFO_KEY_COUNT = "Bag-Count"
    BAG_INFO_KEY_DATE = "Bagging-Date"
    BAG_INFO_VALUE_SOURCE = "University of Michigan"
    BAG_FILE_APTRUST_INFO = "aptrust-info.txt"

    EXT_TAR = ".tar"

    attr_reader :work
    attr_reader :data_transfer

    attr_reader :repository
    attr_reader :context
    attr_reader :description

    attr_reader :status_history

    def initialize(work:, context:, config:, data_transfer:, status_event_repo:)
      @work = work
      @data_transfer = data_transfer
      @working_dir = config.working_dir
      @export_dir = config.export_dir

      @aptrust_config = config.aptrust
      @context = context || ""
      @repository = config.repository.name
      @description = config.repository.description
      @status_event_repo = status_event_repo
    end

    def track!(status:, note: nil)
      status_event = {work_id: @work.id, status: status, timestamp: Time.now}
      if !note.nil?
        status_event[:note] = note
      end
      @status_event_repo.create(status_event)
    end

    def fs_identifier
      IDENTIFIER_TEMPLATE
        .gsub("%repository%", @repository)
        .gsub("%context%", @context)
        .gsub("%id%", @work.id)
    end

    def self.bag_datetime_now
      now_datetime = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      Time.parse(now_datetime).iso8601
    end

    def bag_info
      {
        BAG_INFO_KEY_SOURCE => BAG_INFO_VALUE_SOURCE,
        BAG_INFO_KEY_COUNT => "1",
        BAG_INFO_KEY_DATE => BagCourierService.bag_datetime_now,
        "Internal-Sender-Description" => @description,
        "Internal-Sender-Identifier" => @work.id
      }
    end

    def tar(target_path)
      LOGGER.debug(["target_path=#{target_path}", "work.id=#{@work.id}"])

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
        "work.id=#{@work.id}",
        "new_path=#{new_path}"
      ])
      new_path
    end

    def deposit(file_path:)
      LOGGER.debug([
        "filename=#{file_path}",
        "work.id=#{@work.id}",
        "status_history=#{@status_history}"
      ])

      success = false
      LOGGER.debug("allow_deposit?=#{@@allow_deposit}")
      if !@@allow_deposit
        track!(status: "deposit_skipped")
        return
      end

      begin
        track!(status: "depositing")
        # add timing
        Aws.config.update(
          credentials: Aws::Credentials.new(
            @aptrust_config.aws_access_key_id,
            @aptrust_config.aws_secret_access_key
          )
        )
        s3 = Aws::S3::Resource.new(region: @aptrust_config.bucket_region)
        bucket = s3.bucket(@aptrust_config.bucket)
        aws_object = bucket.object(File.basename(file_path))
        track!(status: "uploading")
        aws_object.upload_file(file_path)
        track!(status: "uploaded")
      rescue Aws::S3::Errors::ServiceError => e
        track!(status: "failed", note: "failed in #{e.context} with error #{e}")
        LOGGER.error(["Upload of file #{filename} failed in #{e.context} with error #{e}"] + e.backtrace[0..20])
        success = false
      end
      track!(status: "deposited") if success
      success
    end

    def perform_deposit
      LOGGER.debug("work.id=#{@work.id}")

      begin
        track!(status: "bagging")
        bag_path = File.join(@working_dir, fs_identifier)
        bag = BagAdapter.new(bag_path)

        track!(status: "copying")
        @data_transfer.transfer(bag.data_dir)
        track!(status: "copied")

        # TO DO: Support more than one tag file
        aptrust_info_text = AptrustInfo.new(work: @work).build
        bag.add_tag_file!(tag_file_text: aptrust_info_text, file_name: BAG_FILE_APTRUST_INFO)

        bag.add_bag_info(bag_info)

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
        # TO DO: delete untarred files

        deposit(file_path: export_tar_file_path)
      rescue => e
        LOGGER.error(
          ["BagCourierService.perform_deposit error #{e}"] + e.backtrace[0..20]
        )
        track!(status: "failed", note: "failed with error #{e}")
      end
    end
  end
end
