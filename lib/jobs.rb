require "time"

require "prometheus/client"
require "prometheus/client/push"
require "prometheus/client/registry"

require_relative "config"
require_relative "bag_status"

module DarkBlueMetrics
  class PushGatewayClientError < StandardError; end

  class Timer
    def self.time_processing
      start_time = Time.now.to_i
      yield
      end_time = Time.now.to_i
      [start_time, end_time]
    end
  end

  class MetricsProvider
    def initialize(start_time:, end_time:, status_event_repo:)
      @start_time = start_time
      @end_time = end_time
      @status_event_repo = status_event_repo
    end

    def get_latest_bag_events_by_time
      st_time = Time.at(@start_time)
      @status_event_repo.get_latest_event_for_bags(start_time: st_time)
    end

    def get_success_count(events_by_time)
      success_count = events_by_time.select { |e| e.status == BagStatus::DEPOSITED }
      success_count.count
    end

    def get_failure_count(events_by_time)
      failure_count = events_by_time.select { |e| e.status == BagStatus::FAILED }
      failure_count.count
    end

    def get_failed_bag_ids(events_by_time)
      events_by_time.select { |e| e.status == BagStatus::FAILED }
    end

    def set_success_count(events_by_time)
      dark_blue_success_count = registry.gauge(
        :dark_blue_success_count,
        docstring: "Successful number of bag transfer"
      )
      dark_blue_success_count.set(get_success_count(events_by_time))
    end

    def set_failed_count(events_by_time)
      dark_blue_failed_count = registry.gauge(
        :dark_blue_failed_count,
        docstring: "Failed number of bag transfer"
      )
      dark_blue_failed_count.set(get_failure_count(events_by_time))
    end

    # def set_failed_bag_id(events_by_time)
    #   dark_blue_failed_bag_ids = registry.counter(
    #     :dark_blue_failed_bag_ids,
    #     docstring: "Failed bag transfer")
    #   get_failed_ids = get_failed_bag_ids(events_by_time)
    #   get_failed_ids.each do |e|
    #     dark_blue_failed_bag_ids.increment({failed_id: e.bag_identifier},0)
    #   end
    # end

    def set_last_successful_run
      dark_blue_last_successful_run = registry.gauge(:dark_blue_last_successful_run,
        docstring: "Timestamp of the last successful run of the cron job")
      return unless dark_blue_last_successful_run
      time_in_milli_sec = (@start_time * 1000)
      dark_blue_last_successful_run.set(time_in_milli_sec)
    end

    def set_processing_duration
      dark_blue_processing_duration = registry.gauge(:dark_blue_processing_duration,
        docstring: "Duration of processing in seconds for the cron job")
      return unless dark_blue_processing_duration
      dark_blue_processing_duration.set(@end_time - @start_time)
    end

    def set_all_metrics
      set_last_successful_run
      set_processing_duration
      latest_events = get_latest_bag_events_by_time
      set_success_count(latest_events)
      set_failed_count(latest_events)
      # set_failed_bag_id(latest_events)
      push_metrics
    end

    private

    def registry
      @registry ||= Prometheus::Client::Registry.new
    end

    def gateway
      @gateway ||= Prometheus::Client::Push.new(
        job: "DarkBlueMetric",
        gateway: Config::ConfigService.push_gateway_from_env
      )
    end

    def push_metrics
      gateway.add(registry)
    end
  end
end
