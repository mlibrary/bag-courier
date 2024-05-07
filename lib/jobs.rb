require "time"
require "prometheus/client"
require "prometheus/client/push"
require "prometheus/client/registry"

require_relative "../db/database_schema" if DB
require_relative "bag_status"
module Jobs
  class DarkBlueMetrics
    class PushGatewayClientError < StandardError; end

    def initialize(start_time:, end_time:)
      @start_time = start_time
      @end_time = end_time
    end

    def get_success_count
      successful_status = [
      BagStatus::BAGGING, BagStatus::COPYING, BagStatus::COPIED, BagStatus::VALIDATING,BagStatus::VALIDATED,
      BagStatus::BAGGED, BagStatus::PACKING,BagStatus::PACKED, BagStatus::DEPOSITING, BagStatus::DEPOSITED]
      success_count = DatabaseSchema::StatusEvent
      .join(:status,  Sequel.qualify(:status, :id) => Sequel.qualify(:status_event, :status_id))
      .where { Sequel.qualify(:status_event,:timestamp) >= @start_time }
      .select( :bag_id, Sequel.qualify(:status, :name))
      .group(:bag_id)
      .having{count(Sequel.qualify(:status, :name)) == successful_status.length}
      .count
      success_count
    end

    def get_failure_count
      failed_status = [BagStatus::DEPOSIT_SKIPPED, BagStatus::FAILED, BagStatus::VALIDATION_SKIPPED, BagStatus::VERIFY_FAILED]
      failure_count = DatabaseSchema::StatusEvent
      .join(:status,  Sequel.qualify(:status, :id) => Sequel.qualify(:status_event, :status_id))
      .where { Sequel.qualify(:status_event,:timestamp) >= @start_time }
      .select( :bag_id, Sequel.qualify(:status, :name))
      .group(:bag_id)
      .having(~Sequel.|(*failed_status.map {|status| Sequel.qualify(:status, :name) => status}))
      .count
      failure_count
    end

    def get_failed_bag_ids
      failed_status = [BagStatus::DEPOSIT_SKIPPED, BagStatus::FAILED, BagStatus::VALIDATION_SKIPPED, BagStatus::VERIFY_FAILED]
      failure_bag_ids = DatabaseSchema::Bag
      .join(:status_event,  Sequel.qualify(:status_event, :bag_id) => Sequel.qualify(:bag, :id))
      .join(:status,  Sequel.qualify(:status, :id) => Sequel.qualify(:status_event, :status_id))
      .where(Sequel.qualify(:status_event, :timestamp) >= @start_time)
      .where(Sequel.qualify(:status, :name).like("%#{failed_status.join('%')}%"))
      .group(Sequel[:bag][:identifier])
      .select_map(Sequel[:bag][:identifier])

      failure_bag_ids
    end

    def set_success_count
      dark_blue_success_count = registry.gauge(
        :dark_blue_success_count,
        docstring: "Successful number of bag transfer")
      dark_blue_success_count.set(get_success_count)
    end

    def set_failed_count
      dark_blue_failed_count = registry.gauge(
        :dark_blue_failed_count,
        docstring: "Failed number of bag transfer")
      dark_blue_failed_count.set(get_failure_count)
    end

    def set_failed_bag_id
      dark_blue_failed_bag_ids = registry.gauge(
        :dark_blue_failed_bag_ids,
        docstring: "Failed bag transfer")
      if !get_failed_bag_ids.empty?
        dark_blue_failed_bag_ids.set(get_failed_bag_ids)
      end
    end

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
      set_success_count
      set_failed_count
      set_failed_bag_id
      push_metrics
    end

    private
    def registry
      @registry ||= Prometheus::Client::Registry.new
    end

    def gateway
      @gateway ||= Prometheus::Client::Push.new(
        job: "DarkBlueMetric",
        gateway: ENV.fetch("PROMETHEUS_PUSH_GATEWAY")
      )
    end

    def push_metrics
      gateway.add(registry)
    end
  end
end
