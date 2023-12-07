module BagTag
  class TagSerializer
    def initialize(data)
      @data = data
    end

    def serialize
      content = ""
      @data.each_pair do |k, v|
        content += "#{k}: #{v}\n"
      end
      content
    end

    def self.serialize(data)
      new(data).serialize
    end
  end

  class BagTag
    @@file_name = "default.txt"

    def build
      raise NotImplementedError
    end
  end

  class AptrustInfoBagTag < BagTag
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

    def file_name
      @@file_name
    end

    def squish(value)
      value.strip.gsub(/\s+/, " ")[0..@@field_length]
    end

    def initialize(
      title:,
      item_description:,
      creator:,
      description: nil,
      access: nil,
      storage_option: nil,
      extra_data: nil,
      serializer: TagSerializer
    )
      @title = squish(title || work.title)
      @description = squish(description || @@default_description)
      @item_description = squish(item_description || work.description)
      @creator = squish(creator || work.creator)
      @access = access || "Institution"
      @storage_option = squish(storage_option || "Standard")
      @extra_data = extra_data
      @serializer = serializer
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
      @serializer.serialize(prep_data)
    end
  end
end
