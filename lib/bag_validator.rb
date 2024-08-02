require "bagit"

class BagValidator
  def validate(path)
    raise NotImplementedError, "subclass must implement the validate method"
  end
end

class InnerBagValidator < BagValidator
  def initialize(inner_bag_name, detect_hidden)
    @inner_bag_name = inner_bag_name
    @detect_hidden = detect_hidden
  end

  def validate(data_path)
    path = File.join(data_path, @inner_bag_name)
    if !Dir.exist?(path)
      raise BagValidationError, "Inner bag path does not exist: #{path}"
    end

    @bag = BagIt::Bag.new(path, {}, false, @detect_hidden)
    validity = @bag.valid?

    if !validity
      raise BagValidationError, "Inner bag is not valid: #{@bag.errors.full_messages.join(", ")}"
    else
      validity
    end
  end
end

class BagValidationError < StandardError
end
