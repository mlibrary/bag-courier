require "logger"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/bag_tag"

LOGGER = Logger.new($stdout)

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
    assert_equal expected, aptrust_info.build
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
    assert_equal expected, aptrust_info.build
  end
end
