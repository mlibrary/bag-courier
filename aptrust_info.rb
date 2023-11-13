class AptrustInfo
  @@default_description = "The Description" # TO DO
  @@field_length = 255

  attr_accessor :access
  attr_accessor :creator
  attr_accessor :description
  attr_accessor :item_description
  attr_accessor :storage_option
  attr_accessor :title

  def squish(value)
    value.strip.gsub(/\s+/, " ")[0..@@field_length]
  end

  def initialize(
    work:,
    access: nil,
    creator: nil,
    description: nil,
    item_description: nil,
    storage_option: nil,
    title: nil
  )
    @access = access || "Institution"
    @creator = squish(creator || work.creator)
    @description = squish(description || @@default_description)
    @item_description = squish(item_description || work.description)
    @storage_option = squish(storage_option || "Standard")
    @title = squish(title || work.title)
  end

  def build(extra_data = nil)
    data = {
      Title: @title,
      Access: @access,
      "Storage-Option": @storage_option,
      Description: @description,
      "Item Description": @item_description,
      "Creator/Author": @creator
    }

    if !extra_data.nil?
      data = data.merge(extra_data)
    end

    content = ""
    data.each_pair do |k, v|
      content += "#{k}: #{v}\n"
    end
    content
  end
end
