require "minitest/autorun"
require "minitest/pride"
require "minitest/mock"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/jobs"

class DarkBlueMetricTest < Minitest::Test
  def setup
    @metrics = Jobs::DarkBlueMetrics.new
    ENV["PROMETHEUS_PUSH_GATEWAY"] = "http://test.xyz"

    @registry = Minitest::Mock.new
    @gateway = Minitest::Mock.new
    @gauge = Minitest::Mock.new
  end

  def test_registry
    result = @metrics.send(:registry)
    assert_instance_of Prometheus::Client::Registry, result
  end

  def test_gateway
    result = @metrics.send(:gateway)
    assert_instance_of Prometheus::Client::Push, result
  end

  def test_push_last_successful_run
    time_now = (Time.now.to_i)
    Time.stub :now, time_now do
      @metrics.push_last_successful_run
    end
    expected_value = time_now * 1000 #millisec
    assert_equal expected_value,@metrics.send(:registry).get(:dark_blue_last_successful_run).get
  end

  def test_push_processing_duration
    expected_duration = 5
    time_now = Time.now
    @metrics.push_processing_duration(time_now,(time_now + expected_duration))
    assert_equal expected_duration, @metrics.send(:registry).get(:dark_blue_processing_duration).get
  end
  # TBD:

  # sleep(30)

  #     labels = {
  #       date_of_processing: Time.at(start_time + (60 * 60 * 24)).strftime("%m/%d/%Y"),
  #       success: 2,
  #       failure: 1
  #     }

  #     bag_transfer_metrics.set(start_time + (60 * 60 * 24) , labels: labels)
  #     gateway.add(registry)

  #     sleep(30)

  #     labels = {
  #       date_of_processing: Time.at(start_time + (60 * 60 * 24 * 2)).strftime("%m/%d/%Y"),
  #       success: 3,
  #       failure: 0
  #     }

  #     bag_transfer_metrics.set(start_time + (60 * 60 * 24 * 2) , labels: labels)
  #     gateway.add(registry)

  #     sleep(30)

  #     labels = {
  #       date_of_processing: Time.at(start_time + (60 * 60 * 24 * 3)).strftime("%m/%d/%Y"),
  #       success: 0,
  #       failure: 4
  #     }

  #     bag_transfer_metrics.set(start_time + (60 * 60 * 24 * 3) , labels: labels)
  #     gateway.add(registry)
end

# class DarkBlueMetricsFactoryTest < Minitest::Test
#   def test_for_creates_db_repo
#     db = Sequel.connect("mock://mysql2")
#     repo = Job::DarkBlueMetricsFactory.for(use_db: db)
#     assert repo.is_a?(Job::DarkBlueMetrics)
#   end

# end
