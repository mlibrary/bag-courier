require "minitest/autorun"
require "minitest/pride"
require "minitest/mock"
require "sequel"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/bag_status"
require_relative "../lib/jobs"

class DarkBlueMetricTest < Minitest::Test
  def setup
    @start_time = Time.now.to_i
    @end_time = @start_time + 5
    @metrics = Jobs::DarkBlueMetrics.new(start_time: @start_time, end_time: @end_time)
    ENV["PROMETHEUS_PUSH_GATEWAY"] = "http://test.xyz"

    @registry_mock = Prometheus::Client::Registry.new
    @gateway_mock = Minitest::Mock.new
    @gauge_mock = Minitest::Mock.new
    @db_mock = Sequel.mock
  end

  def test_initialize
    assert_equal @start_time, @metrics.instance_variable_get(:@start_time)
    assert_equal @end_time, @metrics.instance_variable_get(:@end_time)
  end

  def test_registry
    result = @metrics.send(:registry)
    assert_instance_of Prometheus::Client::Registry, result
  end

  def test_gateway
    result = @metrics.send(:gateway)
    assert_instance_of Prometheus::Client::Push, result
  end

  def test_set_last_successful_run
    expected_time = (@start_time * 1000)
    @registry_mock.stub(:gauge, @gauge_mock) do
      actual_time = @metrics.set_last_successful_run
      @gauge_mock.verify
      assert_equal(expected_time, actual_time)
    end
  end

  def test_set_processing_duration
    expect_duration = @end_time - @start_time
    @registry_mock.stub(:gauge, @gauge_mock) do
      actual_duration = @metrics.set_processing_duration
      @gauge_mock.verify
      assert_equal(expect_duration, actual_duration)
    end
  end

  def test_get_failed_bag_ids
    failed_status = [BagStatus::DEPOSIT_SKIPPED, BagStatus::FAILED, BagStatus::VALIDATION_SKIPPED, BagStatus::VERIFY_FAILED]

    bag_mock = Minitest::Mock.new
    bag_mock.expect(:join, bag_mock,[:status_event,  Sequel.qualify(:status_event, :bag_id) => Sequel.qualify(:bag, :id)])
    bag_mock.expect(:join, bag_mock, [:status,  Sequel.qualify(:status, :id) => Sequel.qualify(:status_event, :status_id)])
    bag_mock.expect(:where, bag_mock, [Sequel.qualify(:status_event, :timestamp) >= @start_time])
    bag_mock.expect(:where, bag_mock, [Sequel.qualify(:status, :name).like("%#{failed_status.join('%')}%")])
    bag_mock.expect(:group, bag_mock, [Sequel[:bag][:identifier]])
    bag_mock.expect(:select_map, ['4355a','hgfb5'], Sequel[:bag][:identifier])

    DatabaseSchema::Bag.stub(:call, bag_mock) do
      failed_bag_ids = @metrics.get_failed_bag_ids
      expected_bag_ids = ['4355a','hgfb5']
      assert_equal expected_bag_ids, failed_bag_ids
    end
  end
end
