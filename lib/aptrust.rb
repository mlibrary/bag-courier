module Aptrust
  class AptrustInfo
    @@file_name = "aptrust-info.txt"
    @@default_description = "Bag deposited to APTrust"
    @@field_length = 255

    attr_reader :title,
      :item_description,
      :creator,
      :description,
      :access,
      :storage_option,
      :extra_data

    def self.write(data)
      content = ""
      data.each_pair do |k, v|
        content += "#{k}: #{v}\n"
      end
      content
    end

    def self.file_name
      @@file_name
    end

    def self.squish(value)
      value.strip.gsub(/\s+/, " ")[0..@@field_length]
    end

    def initialize(
      title:,
      item_description:,
      creator:,
      description: nil,
      access: nil,
      storage_option: nil,
      extra_data: nil
    )
      @title = AptrustInfo.squish(title || work.title)
      @description = AptrustInfo.squish(description || @@default_description)
      @item_description = AptrustInfo.squish(item_description || work.description)
      @creator = AptrustInfo.squish(creator || work.creator)
      @access = access || "Institution"
      @storage_option = AptrustInfo.squish(storage_option || "Standard")
      @extra_data = extra_data
    end

    def prep_data
      data = {
        Title: @title,
        Description: @description,
        "Item Description": @item_description,
        "Creator/Author": @creator,
        Access: @access,
        "Storage-Option": @storage_option
      }
      if !@extra_data.nil?
        data = data.merge(@extra_data)
      end
      data
    end

    def build
      AptrustInfo.write(prep_data)
    end
  end
end
