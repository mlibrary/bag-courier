require "minitest/autorun"
require "minitest/pride"
require "minitest/mock"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/jobs"

class DarkBlueMetricTest < Minitest::Test
  def setup
    @time_now = Time.now
    @metrics = Jobs::DarkBlueMetrics.new(start_time: @time_now, end_time:(@time_now + 5))
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

  # def test_set_last_successful_run
  #   expected_time = @time_now * 1000
  #   @gauge.expect(:set, nil,[expected_time])

  #   @metrics.stub(:create_gauge, @gauge) do
  #     Time.stub :now, Time.at(expected_time) do
  #       @metrics.set_last_successful_run
  #     end
  #   end
  #   @gauge.verify
  # end

  # def test_set_processing_duration
  #   expected_duration = 5
  #   @gauge.expect(:set, nil,[expected_duration])

  #   @metrics.stub(:create_gauge, @gauge) do
  #     Time.stub :now, Time.at(expected_duration) do
  #       @metrics.set_processing_duration
  #     end
  #   end
  #   @gauge.verify
  # end
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
