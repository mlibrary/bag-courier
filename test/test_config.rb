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
end
