require "time"
require "prometheus/client"
require "prometheus/client/push"
require "prometheus/client/registry"

require_relative "../db/database_schema" if DB
require_relative "bag_status"
module Jobs
  class DarkBlueMetrics

    # for being unable to contact the push gateway
    class PushGatewayClientError < StandardError; end


    def get_overall_metrics_current_run(start_time)
      successful_transfer_status = [
      BagStatus::BAGGING, BagStatus::COPYING, BagStatus::COPIED, BagStatus::VALIDATING,BagStatus::VALIDATED,
      BagStatus::BAGGED, BagStatus::PACKING,BagStatus::PACKED, BagStatus::DEPOSITING, BagStatus::DEPOSITED
     ]

      # failed_transfer_status = [
      #   BagStatus::FAILED, BagStatus::DEPOSIT_SKIPPED, BagStatus::VALIDATION_SKIPPED, BagStatus::VERIFY_FAILED
      # ]
      result = DatabaseSchema::StatusEvent
      .join(:status,  Sequel.qualify(:status, :id) => Sequel.qualify(:status_event, :status_id))
      .join(:bag,  Sequel.qualify(:bag, :id) => Sequel.qualify(:status_event, :bag_id))
      .where { Sequel.qualify(:status_event,:timestamp) >= start_time }
      .select(:timestamp, Sequel.qualify(:status, :name).as(:status_name), Sequel.qualify(:bag, :identifier).as(:bag_id),
      Sequel.as(Sequel.function(:COUNT, Sequel.case({{Sequel.qualify(:status, :id) => successful_transfer_status} => 1}, 0)),
      :success_count))

      successful_bag_transfer = []
      failed_bag_transfer = []

      # successful transfer
      result.each do |row|
        if row[:success_count]==successful_transfer_status.length
          successful_bag_transfer << row[:bag_id]
        else
          failed_bag_transfer << row[:bag_id]
        end
      end
      bag_transfer_metrics = registry.gauge(
        :bag_transfer_metrics,
        docstring: "Bag transfer metrics",
        labels: [:date_of_processing , :success, :failure]
      )
      labels = {
        date_of_processing: Time.at(start_time).strftime("%m/%d/%Y"),
        success: successful_bag_transfer.count,
        failure: failed_bag_transfer.count
      }

      bag_transfer_metrics.set(start_time, labels: labels)
      gateway.add(registry)

      successful_bag_id = registry.gauge(
        :successful_bag_id,
        docstring: "Successful Bag transfer metrics",
        labels: [:bag_id]
      )

      labels = {
        bag_id: successful_bag_transfer
      }

      successful_bag_id.set(start_time, labels: labels)
      gateway.add(registry)

      failed_bag_id = registry.gauge(
        :failed_bag_id,
        docstring: "Failed Bag transfer metrics",
        labels: [:bag_id]
      )

      labels = {
        bag_id: failed_bag_transfer
      }

      failed_bag_id.set(start_time, labels: labels)
      gateway.add(registry)
    end

    def push_last_successful_run
      dark_blue_last_successful_run = registry.gauge(
        :dark_blue_last_successful_run,
        {docstring: "Timestamp of the last successful run of the cron job"}
    )
      time_in_milli_sec = (Time.now.to_i) * 1000
      dark_blue_last_successful_run.set(time_in_milli_sec)
      gateway.add(registry)
    end

    def push_processing_duration(start_time, end_time)
      dark_blue_processing_duration = registry.gauge(
        :dark_blue_processing_duration,
        {docstring: "Duration of processing in seconds for the cron job"}
      )
      dark_blue_processing_duration.set(end_time - start_time)
      gateway.add(registry)
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

  end

  # class DarkBlueMetricsFactory
  #   def self.for(use_db:)
  #     DarkBlueMetrics.new if use_db?
  #   end
  # end
end
