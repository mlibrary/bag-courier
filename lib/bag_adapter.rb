require "bagit"

require_relative "../services"

module BagAdapter
  ValidationResult = Struct.new(
    "ValidationResult",
    :is_valid,
    :error_message,
    keyword_init: true
  )

  class BagAdapter
    include DarkBlueLogger

    attr_reader :additional_tag_files

    def initialize(target_dir:, detect_hidden: true)
      @bag = BagIt::Bag.new(target_dir, {}, false, detect_hidden)
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
      file_path = File.join(@bag.bag_dir, file_name)
      File.write(file_path, tag_file_text, mode: "w")
      @additional_tag_files << file_path
    end

    def add_manifests
      logger.debug([
        "bag.tag_files=#{@bag.tag_files}",
        "additional_tag_files=#{@additional_tag_files}"
      ])
      @bag.manifest!(algo: "md5") # Create manifests

      # Rewrite the tag manifest files to include extra tag files
      tag_files_set = Set.new(@bag.tag_files)
      new_tag_files_set = tag_files_set | Set.new(@additional_tag_files)
      logger.debug("new_tag_files_set=#{new_tag_files_set}")
      @bag.tagmanifest!(new_tag_files_set.to_a) unless (new_tag_files_set - tag_files_set).empty?

      # HELIO-4380 demo.aptrust.org doesn't like this file for some reason, gives an ingest error:
      # "Bag contains illegal tag manifest 'sha1'""
      # APTrust only wants SHA256, or MD5, not SHA1.
      # 'tagmanifest-sha1.txt' is a bagit gem default, so we need to remove it manually.
      sha1tag = File.join(@bag.bag_dir, "tagmanifest-sha1.txt")
      File.delete(sha1tag) if File.exist?(sha1tag)
    end

    def check_if_valid
      is_valid = @bag.valid?
      ValidationResult.new(
        is_valid: is_valid,
        error_message: is_valid ? nil : @bag.errors.full_messages.join(", ")
      )
    end
  end
end
