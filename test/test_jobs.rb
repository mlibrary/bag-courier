require "minitest/autorun"
require "minitest/pride"
require "minitest/mock"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/bag_status"
require_relative "../lib/bag_repository"
require_relative "../lib/jobs"
require_relative "../lib/repository_package_repository"
require_relative "../lib/status_event_repository"



class DarkBlueMetricTest < Minitest::Test
  def setup
    @start_time = Time.utc(2024, 2, 4, 12, 0, 0, 0)
    @end_time = @start_time + 5
    @status_event_repo = StatusEventRepository::StatusEventDatabaseRepository.new
    @bag_repo = BagRepository::BagDatabaseRepository.new
    @bag_identifier = "repository.context-004"

    @package_repo = RepositoryPackageRepository::RepositoryPackageDatabaseRepository.new
    @package_identifier = "000004"

    fifth_package_identifier = "000005"
    mixin_package_repo.create(identifier: mixin_package_identifier, repository_name: "repository-1", updated_at: Time.now.utc)
    mixin_package_repo.create(identifier: fifth_package_identifier, repository_name: "repository-1", updated_at: Time.now.utc)

    bag_identifier_four = mixin_bag_identifier
    bag_identifier_five = "repository.context-005"

    mixin_bag_repo.create(identifier: bag_identifier_four, group_part: 1, repository_package_identifier: mixin_package_identifier)
    mixin_bag_repo.create(identifier: bag_identifier_five, group_part: 1, repository_package_identifier: fifth_package_identifier)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_identifier_four, timestamp: @start_time)
    mixin_repo.create(status: BagStatus::DEPOSITED, bag_identifier: bag_identifier_four, timestamp: @start_time + 95 )
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_identifier_five, timestamp: @start_time + 100)
    mixin_repo.create(status: BagStatus::FAILED, bag_identifier: bag_identifier_five, timestamp: @start_time + 120)

    @metrics = DarkBlueMetrics::MetricsProvider.new(start_time: @start_time, end_time: @end_time, status_event:@status_event_repo)

    @registry_mock = Prometheus::Client::Registry.new
    @gateway_mock = Minitest::Mock.new
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

  def test_get_latest_bag_events_by_time
    status_events = mixin_repo.get_all
    p status_events
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
end
