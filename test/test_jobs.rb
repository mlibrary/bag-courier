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
    @gauge.expect(:set, nil,[Numeric])
    @registry.expect(:gauge, @gauge,[:dark_blue_last_successful_run,
        {docstring: "Timestamp of the last successful run of the cron job"}
     ])
    @gateway.expect(:add, nil, [@registry])

    @metrics.instance_variable_set(:@registry, @registry)
    @metrics.instance_variable_set(:@gateway, @gateway)
    @metrics.push_last_successful_run
    @registry.verify
    @gauge.verify
    @gateway.verify
  end

  def test_push_processing_duration
    expected_duration = 5
    time_now = Time.now
    @gauge.expect(:set, nil,[Numeric])
    @registry.expect(:gauge, @gauge,[:dark_blue_processing_duration,{docstring: "Duration of processing in seconds for the cron job"} ])
    @gateway.expect(:add, nil, [@registry])

    @metrics.instance_variable_set(:@registry, @registry)
    @metrics.instance_variable_set(:@gateway, @gateway)
    @metrics.push_processing_duration(time_now,(time_now + expected_duration))
    @registry.verify
    @gauge.verify
    @gateway.verify
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
