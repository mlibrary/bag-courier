require "logger"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/aptrust"

LOGGER = Logger.new($stdout)

class AptrustInfoTest < Minitest::Test
  @@base_test_data = {
    title: "Some Object",
    description: "A bag from a repository containing preserved item",
    item_description: "An item being preserved",
    creator: "Unknown"
  }

  def test_build
    aptrust_info = Aptrust::AptrustInfo.new(**@@base_test_data)
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

  def test_build_with_extra_data
    test_data = @@base_test_data.merge({extra_data: {Context: "Some important detail"}})
    LOGGER.info(test_data)
    aptrust_info = Aptrust::AptrustInfo.new(**test_data)
    LOGGER.info(aptrust_info.build)
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
