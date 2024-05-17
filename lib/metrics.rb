require "time"

require "prometheus/client"
require "prometheus/client/push"
require "prometheus/client/registry"

require_relative "../services"
require_relative "bag_status"

module Metrics
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
    def initialize(
      status_event_repo:,
      push_gateway_url:,
      start_time:,
      end_time:,
      registry: nil
    )
      @start_time = start_time
      @end_time = end_time
      @status_event_repo = status_event_repo
      @push_gateway_url = push_gateway_url
      @registry = registry
    end

    def registry
      @registry ||= Prometheus::Client::Registry.new
    end
    private :registry

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

    def set_success_count(events_by_time)
      dark_blue_success_count = registry.gauge(
        :dark_blue_success_count,
        docstring: "Number of successful bag transfers"
      )
      dark_blue_success_count.set(get_success_count(events_by_time))
    end

    def set_failed_count(events_by_time)
      dark_blue_failed_count = registry.gauge(
        :dark_blue_failed_count,
        docstring: "Number of failed bag transfers"
      )
      dark_blue_failed_count.set(get_failure_count(events_by_time))
    end

    def set_last_successful_run
      dark_blue_last_successful_run = registry.gauge(
        :dark_blue_last_successful_run,
        docstring: "Timestamp of the last successful run of the cron job"
      )
      # converting starttime to milliseconds to support converting epoch time to datetime
      # https://github.com/grafana/grafana/issues/6297
      time_in_milli_sec = @start_time * 1000
      dark_blue_last_successful_run.set(time_in_milli_sec)
    end

    def set_processing_duration
      dark_blue_processing_duration = registry.gauge(
        :dark_blue_processing_duration,
        docstring: "Duration of processing in seconds for the cron job"
      )
      dark_blue_processing_duration.set(@end_time - @start_time)
    end

    def gateway
      @gateway ||= Prometheus::Client::Push.new(
        job: "DarkBlueMetric",
        gateway: @push_gateway_url
      )
    end
    private :gateway

    def push_metrics
      gateway.add(registry)
    end
    private :push_metrics

    def set_all_metrics
      set_last_successful_run
      set_processing_duration
      latest_events = get_latest_bag_events_by_time
      set_success_count(latest_events)
      set_failed_count(latest_events)
      push_metrics
    end
  end
end
