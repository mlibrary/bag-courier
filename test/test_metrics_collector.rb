require "minitest/autorun"
require "minitest/pride"
require "minitest/mock"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/bag_status"
require_relative "../lib/bag_repository"
require_relative "../lib/metrics_collector"
require_relative "../lib/repository_package_repository"
require_relative "../lib/status_event_repository"

class DarkBlueMetricTest < Minitest::Test
  def setup
    @time_stamp = Time.utc(2024, 3, 4, 12, 0, 0, 0)
    @start_time = @time_stamp.to_i
    @end_time = @start_time + 5
    @package_repo = RepositoryPackageRepository::RepositoryPackageDatabaseRepository.new
    @bag_repo = BagRepository::BagDatabaseRepository.new
    @status_event_repo = StatusEventRepository::StatusEventDatabaseRepository.new
    @object_id = "000001"
    @repository_name = "fake-repository"
    @bag_identifier_one = "repository.context-000001"
    @bag_identifier_two = "repository.context-000002"
    @package_repo.create(
      identifier: @object_id,
      repository_name: @repository_name,
      updated_at: Time.now.utc
    )
    @bag_repo.create(
      identifier: @bag_identifier_one,
      group_part: 1,
      repository_package_identifier: @object_id
    )
    @status_event_repo.create(
      status: BagStatus::DEPOSITED,
      bag_identifier: @bag_identifier_one,
      timestamp: @time_stamp,
      note: "something happening here"
    )

    @bag_repo.create(
      identifier: @bag_identifier_two,
      group_part: 3,
      repository_package_identifier: @object_id
    )
    @status_event_repo.create(
      status: BagStatus::FAILED,
      bag_identifier: @bag_identifier_two,
      timestamp: @time_stamp,
      note: "something happening here"
    )

    @metrics = DarkBlueMetrics::MetricsProvider.new(start_time: @start_time, end_time: @end_time, status_event_repo: @status_event_repo)

    @registry = Prometheus::Client::Registry.new
    @gauge_mock = Minitest::Mock.new
  end

  def mixin_repo
    @status_event_repo
  end

  def mixin_bag_repo
    @bag_repo
  end

  def mixin_bag_identifier
    @bag_identifier
  end

  def mixin_package_repo
    @package_repo
  end

  def mixin_package_identifier
    @package_identifier
  end

  def test_initialize
    assert_equal @start_time, @metrics.instance_variable_get(:@start_time)
    assert_equal @end_time, @metrics.instance_variable_get(:@end_time)
  end

  def test_set_last_successful_run
    expected_time = (@start_time.to_i * 1000)
    @registry.stub(:gauge, @gauge_mock) do
      actual_time = @metrics.set_last_successful_run
      @gauge_mock.verify
      assert_equal(expected_time, actual_time)
    end
  end

  def test_set_processing_duration
    expect_duration = @end_time - @start_time
    @registry.stub(:gauge, @gauge_mock) do
      actual_duration = @metrics.set_processing_duration
      @gauge_mock.verify
      assert_equal(expect_duration, actual_duration)
    end
  end

  def test_set_success_count
    expected = 1
    @registry.stub(:gauge, @gauge_mock) do
      events_by_time = @metrics.get_latest_bag_events_by_time
      actual = @metrics.set_success_count(events_by_time)
      @gauge_mock.verify
      assert_equal(expected, actual)
    end
  end

  def test_set_failed_count
    expected = 1
    @registry.stub(:gauge, @gauge_mock) do
      events_by_time = @metrics.get_latest_bag_events_by_time
      actual = @metrics.set_failed_count(events_by_time)
      @gauge_mock.verify
      assert_equal(expected, actual)
    end
  end

  def test_get_latest_bag_events_by_time
    actual_result = @metrics.get_latest_bag_events_by_time
    assert_equal 2, actual_result.length
  end

  def test_get_success_count
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_success_count(events_by_time)
    assert_equal 1, actual_result
  end

  def test_get_failure_count
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_failure_count(events_by_time)
    assert_equal 1, actual_result
  end

  def test_get_failed_bag_ids
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_failed_bag_ids(events_by_time)
    assert_equal "repository.context-000002", actual_result[0].bag_identifier
  end
end
