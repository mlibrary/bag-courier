require "minitest/autorun"
require "minitest/pride"
require "minitest/mock"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/bag_status"
require_relative "../lib/jobs"
require_relative "../lib/status_event_repository"


class DarkBlueMetricTest < Minitest::Test
  def setup
    @start_time = Time.now.to_i
    @end_time = @start_time + 5
    @status_event_repo = StatusEventRepository::StatusEventDatabaseRepository.new
    @metrics = DarkBlueMetrics::MetricsProvider.new(start_time: @start_time, end_time: @end_time, status_event:@status_event_repo)

    @registry_mock = Prometheus::Client::Registry.new
    @gateway_mock = Minitest::Mock.new
    @gauge_mock = Minitest::Mock.new
    @db_mock = Sequel.mock
  end

  def test_initialize
    assert_equal @start_time, @metrics.instance_variable_get(:@start_time)
    assert_equal @end_time, @metrics.instance_variable_get(:@end_time)
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
end
