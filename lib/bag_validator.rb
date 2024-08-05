require_relative "bag_adapter"

class BagValidator
  def validate(path)
    raise NotImplementedError, "subclass must implement the validate method"
  end
end

class InnerBagValidator < BagValidator
  def initialize(inner_bag_name:, detect_hidden: true)
    @inner_bag_name = inner_bag_name
    @detect_hidden = detect_hidden
  end

  def validate(data_path)
    path = File.join(data_path, @inner_bag_name)
    if !Dir.exist?(path)
      raise BagValidationError, "Inner bag path does not exist: #{path}"
    end

    bag = BagAdapter::BagAdapter.new(
      target_dir: path, detect_hidden: @detect_hidden
    )
    result = bag.check_if_valid

    if !result.is_valid
      raise BagValidationError, "Inner bag is not valid: #{result.error_message}"
    else
      result.is_valid
    end
  end
end

class BagValidationError < StandardError
end
