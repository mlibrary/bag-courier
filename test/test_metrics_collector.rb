require "minitest/autorun"
require "minitest/pride"
require "minitest/mock"

require_relative "setup_db"
require_relative "../lib/bag_status"
require_relative "../lib/bag_repository"
require_relative "../lib/metrics_collector"
require_relative "../lib/repository_package_repository"
require_relative "../lib/status_event_repository"

class DarkBlueMetricTest < Minitest::Test
  def setup
    @time_stamp = Time.utc(2024, 1, 4, 12, 0, 0, 0)
    @start_time = @time_stamp.to_i
    @end_time = @start_time + 5
    @status_event_repo = StatusEventRepository::StatusEventInMemoryRepository.new
    @push_gateway_url = "http://fake.pushgateway"

    @registry = Minitest::Mock.new
    @gauge_mock = Minitest::Mock.new

    @metrics = DarkBlueMetrics::MetricsProvider.new(
      start_time: @start_time,
      end_time: @end_time,
      status_event_repo: @status_event_repo,
      push_gateway_url: @push_gateway_url,
      registry: @registry
    )
  end

  def test_set_last_successful_run
    expected_time = (@start_time.to_i * 1000)
    @registry.expect(
      :gauge,
      @gauge_mock,
      [:dark_blue_last_successful_run],
      docstring: "Timestamp of the last successful run of the cron job"
    )
    @gauge_mock.expect(:set, nil, [expected_time])
    @metrics.set_last_successful_run
    @gauge_mock.verify
  end

  def test_set_processing_duration
    expected_duration = 5
    @registry.expect(
      :gauge,
      @gauge_mock,
      [:dark_blue_processing_duration],
      docstring: "Duration of processing in seconds for the cron job"
    )
    @gauge_mock.expect(:set, nil, [expected_duration])
    @metrics.set_processing_duration
    @gauge_mock.verify
  end

  def test_set_success_count
    @bag_identifier_one = "repository.context-0001"
    @bag_identifier_two = "repository.context-0002"
    @deposited_at = Time.utc(2024, 3, 18)

    @status_event_repo.create(
      bag_identifier: @bag_identifier_one,
      status: BagStatus::DEPOSITED,
      timestamp: @deposited_at
    )

    @status_event_repo.create(
      bag_identifier: @bag_identifier_two,
      status: BagStatus::FAILED,
      timestamp: @deposited_at
    )

    @registry.expect(
      :gauge,
      @gauge_mock,
      [:dark_blue_success_count],
      docstring: "Number of successful bag transfers"
    )
    expected = 1
    events_by_time = @metrics.get_latest_bag_events_by_time
    @gauge_mock.expect(:set, nil, [expected])
    @metrics.set_success_count(events_by_time)
    @gauge_mock.verify
  end

  def test_set_failed_count
    @bag_identifier_one = "repository.context-0001"
    @bag_identifier_two = "repository.context-0002"
    @deposited_at = Time.utc(2024, 3, 18)

    @status_event_repo.create(
      bag_identifier: @bag_identifier_one,
      status: BagStatus::DEPOSITED,
      timestamp: @deposited_at
    )

    @status_event_repo.create(
      bag_identifier: @bag_identifier_two,
      status: BagStatus::FAILED,
      timestamp: @deposited_at
    )
    expected = 1
    @registry.expect(
      :gauge,
      @gauge_mock,
      [:dark_blue_failed_count],
      docstring: "Number of failed bag transfers"
    )
    events_by_time = @metrics.get_latest_bag_events_by_time
    @gauge_mock.expect(:set, nil, [expected])
    @metrics.set_failed_count(events_by_time)
    @gauge_mock.verify
  end

  def test_get_latest_bag_events_by_time
    @bag_identifier_one = "repository.context-0001"
    @bag_identifier_two = "repository.context-0002"
    @deposited_at = Time.utc(2024, 3, 18)

    @status_event_repo.create(
      bag_identifier: @bag_identifier_one,
      status: BagStatus::DEPOSITED,
      timestamp: @deposited_at
    )

    @status_event_repo.create(
      bag_identifier: @bag_identifier_two,
      status: BagStatus::FAILED,
      timestamp: @deposited_at
    )
    actual_result = @metrics.get_latest_bag_events_by_time
    assert_equal 2, actual_result.length
  end

  def test_get_success_count
    @bag_identifier_one = "repository.context-0001"
    @bag_identifier_two = "repository.context-0002"
    @deposited_at = Time.utc(2024, 3, 18)

    @status_event_repo.create(
      bag_identifier: @bag_identifier_one,
      status: BagStatus::DEPOSITED,
      timestamp: @deposited_at
    )

    @status_event_repo.create(
      bag_identifier: @bag_identifier_two,
      status: BagStatus::FAILED,
      timestamp: @deposited_at
    )
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_success_count(events_by_time)
    assert_equal 1, actual_result
  end

  def test_get_failure_count
    @bag_identifier_one = "repository.context-0001"
    @bag_identifier_two = "repository.context-0002"
    @deposited_at = Time.utc(2024, 3, 18)

    @status_event_repo.create(
      bag_identifier: @bag_identifier_one,
      status: BagStatus::DEPOSITED,
      timestamp: @deposited_at
    )

    @status_event_repo.create(
      bag_identifier: @bag_identifier_two,
      status: BagStatus::FAILED,
      timestamp: @deposited_at
    )
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_failure_count(events_by_time)
    assert_equal 1, actual_result
  end

  def test_get_failed_bag_ids
    @bag_identifier_one = "repository.context-0001"
    @bag_identifier_two = "repository.context-0002"
    @deposited_at = Time.utc(2024, 3, 18)

    @status_event_repo.create(
      bag_identifier: @bag_identifier_one,
      status: BagStatus::DEPOSITED,
      timestamp: @deposited_at
    )

    @status_event_repo.create(
      bag_identifier: @bag_identifier_two,
      status: BagStatus::FAILED,
      timestamp: @deposited_at
    )
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_failed_bag_ids(events_by_time)
    assert_equal "repository.context-0002", actual_result[0].bag_identifier
  end

  def test_get_latest_bag_events_by_time_empty_array
    actual_result = @metrics.get_latest_bag_events_by_time
    assert_equal [], actual_result
  end

  def test_get_success_count_nil
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_success_count(events_by_time)
    assert_equal 0, actual_result
  end

  def test_get_failure_count_nil
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_failure_count(events_by_time)
    assert_equal 0, actual_result
  end

  def test_get_failed_bag_ids_nil
    events_by_time = @metrics.get_latest_bag_events_by_time
    actual_result = @metrics.get_failed_bag_ids(events_by_time)
    assert_equal [], actual_result
  end
end
