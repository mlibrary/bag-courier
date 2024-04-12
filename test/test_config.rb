require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/config"

class CheckableDataTest < Minitest::Test
  include Config

  def test_get_value_when_it_exists
    data = CheckableData.new({"some_key" => "some_value"})
    assert_equal "some_value", data.get_value(key: "some_key")
  end

  def test_get_value_when_key_does_not_exist
    data = CheckableData.new({})
    expected_message = "Value \"\" for key \"some_key\" is not valid. NotNilCheck failed."
    error = assert_raises(ConfigError) { data.get_value(key: "some_key") }
    assert_equal expected_message, error.message
  end

  def test_get_value_when_key_does_not_exist_but_optional
    data = CheckableData.new({})
    error = assert_raises(ConfigError) { data.get_value(key: "some_key") }
    assert_nil data.get_value(key: "some_key", optional: true)
  end

  def test_get_value_with_integer_string
    data = CheckableData.new({"some_key" => "111"})
    assert_equal "111", data.get_value(key: "some_key", checks: [IntegerCheck.new])
  end

  def test_get_value_with_invalid_integer_string
    data = CheckableData.new({"some_key" => "11a1"})
    expected_message = "Value \"11a1\" for key \"some_key\" is not valid. IntegerCheck failed."
    error = assert_raises(ConfigError) { data.get_value(key: "some_key", checks: [IntegerCheck.new]) }
    assert_equal expected_message, error.message
  end

  def test_get_value_with_valid_boolean_string
    data = CheckableData.new({"some_key" => "true"})
    assert_equal "true", data.get_value(key: "some_key", checks: [BooleanCheck.new])
  end

  def test_get_value_with_invalid_boolean_string
    data = CheckableData.new({"some_key" => "YES!!"})
    expected_message = "Value \"YES!!\" for key \"some_key\" is not valid. BooleanCheck failed."
    error = assert_raises(ConfigError) { data.get_value(key: "some_key", checks: [BooleanCheck.new]) }
    assert_equal expected_message, error.message
  end

  def test_get_subset_by_key_stem
    input = {"namespace_a" => "1", "namespace_b" => "2", "namespace_c" => "3"}
    data = CheckableData.new(input)
    data_subset = data.get_subset_by_key_stem("namespace_")
    assert data_subset.is_a?(CheckableData)
    expected = {"a" => "1", "b" => "2", "c" => "3"}
    assert_equal expected, data_subset.data
  end

  def test_get_subset_by_key_stem_with_no_matches
    input = {"A_blah" => 1, "B_blah" => 2}
    data = CheckableData.new(input)
    data_subset = data.get_subset_by_key_stem("C_")
    assert_equal Hash.new, data_subset.data
  end
end
