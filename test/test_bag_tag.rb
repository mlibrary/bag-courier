require "logger"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/bag_tag"

LOGGER = Logger.new($stdout)

class BagInfoBagTagTest < Minitest::Test
  def test_bag_info_tag_data
    Time.stub :now, Time.new(2023, 12, 7, 12, 0, 0, "UTC") do
      bag_info = BagTag::BagInfoBagTag.new(
        identifier: "5494124",
        description: "Bag from repository X containing item to be preserved"
      )
      data = {
        "Source-Organization" => "University of Michigan",
        "Bag-Count" => "1 of 1",
        "Bagging-Date" => "2023-12-07T12:00:00Z",
        "Internal-Sender-Identifier" => "5494124",
        "Internal-Sender-Description" => "Bag from repository X containing item to be preserved"
      }
      assert_equal data, bag_info.data
    end
  end
end

class AptrustInfoBagTagTest < Minitest::Test
  @@base_test_data = {
    title: "Some Object",
    description: "A bag from a repository containing preserved item",
    item_description: "An item being preserved",
    creator: "Unknown"
  }

  def test_aptrust_tag_build
    aptrust_info = BagTag::AptrustInfoBagTag.new(**@@base_test_data)
    expected = <<~TEXT
      Title: Some Object
      Description: A bag from a repository containing preserved item
      Item Description: An item being preserved
      Creator/Author: Unknown
      Access: Institution
      Storage-Option: Standard
    TEXT
    assert_equal expected, aptrust_info.serialize
  end

  def test_aptrust_tag_build_with_extra_data
    test_data = @@base_test_data.merge({extra_data: {Context: "Some important detail"}})
    aptrust_info = BagTag::AptrustInfoBagTag.new(**test_data)
    expected = <<~TEXT
      Title: Some Object
      Description: A bag from a repository containing preserved item
      Item Description: An item being preserved
      Creator/Author: Unknown
      Access: Institution
      Storage-Option: Standard
      Context: Some important detail
    TEXT
    assert_equal expected, aptrust_info.serialize
  end
end
