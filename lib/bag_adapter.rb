require "bagit"

LOGGER = Logger.new($stdout)

module BagAdapter
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
end
