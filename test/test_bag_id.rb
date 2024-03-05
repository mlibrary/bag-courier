require "logger"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/bag_id"

class BagIdTest < Minitest::Test
  include BagId

  def test_to_s
    expected = "somerepo.uniqueid"
    assert_equal expected, BagId.new(
      repository: "somerepo", object_id: "uniqueid"
    ).to_s
  end

  def test_to_s_with_context
    expected = "somerepo.somecontext-uniqueid"
    assert_equal expected, BagId.new(
      repository: "somerepo", object_id: "uniqueid", context: "somecontext"
    ).to_s
  end

  def test_to_s_with_part
    expected = "somerepo.uniqueid-4"
    assert_equal expected, BagId.new(
      repository: "somerepo", object_id: "uniqueid", part_id: "4"
    ).to_s
  end

  def test_to_s_with_context_and_part
    expected = "somerepo.somecontext-uniqueid-4"
    assert_equal expected, BagId.new(
      repository: "somerepo",
      object_id: "uniqueid",
      context: "somecontext",
      part_id: "4"
    ).to_s
  end
end
