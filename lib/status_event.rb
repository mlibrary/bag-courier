require "semantic_logger"
require "sequel"

Sequel.default_timezone = :utc

module StatusEvent
  class UnknownStatusError < StandardError
  end

  STATUSES = %w[
    bagged bagging
    copied copying
    deposit_skipped deposited depositing
    failed
    packed packing
  ]

  StatusEvent = Struct.new(
    "StatusEvent",
    :id,
    :bag_id,
    :status,
    :timestamp,
    :note,
    keyword_init: true
  )

  class StatusEventRepositoryBase
    def create(event_data)
      raise NotImplementedError
    end

    def get_all
      raise NotImplementedError
    end

    def get_all_for_bag_id(id)
      raise NotImplementedError
    end
  end

  class StatusEventInMemoryRepository < StatusEventRepositoryBase
    attr_reader :status_events

    def initialize(status_events = nil)
      @id = 0
      @status_events = status_events.nil? ? [] : status_events
    end

    def get_next_id!
      id = @id
      @id += 1
      id
    end
    private :get_next_id!

    def create(event_data)
      if !STATUSES.include?(event_data[:status])
        raise UnknownStatusError
      end
      event = StatusEvent.new(
        id: get_next_id!,
        bag_id: event_data[:bag_id],
        status: event_data[:status],
        timestamp: event_data[:timestamp],
        note: event_data[:note]
      )
      @status_events << event
    end

    def get_by_id(id)
      @status_events.find { |e| e.id == id }
    end

    def get_all
      @status_events
    end

    def get_all_for_bag_id(bag_id)
      @status_events.select { |e| e.bag_id == bag_id }
    end
  end

  class StatusEventDatabaseRepository
    include SemanticLogger::Loggable

    def initialize(db)
      @db = db
    end

    def create(event_data)
      logger.debug(event_data)

      # Handle statuses
      status_name = event_data[:status]
      if !STATUSES.include?(status_name)
        raise UnknownStatusError
      end
      statuses = @db.from(:status)
      matching_status = statuses.first(name: status_name)
      status_id = if matching_status
        matching_status[:id]
      else
        statuses.insert(name: status_name)
      end

      bag_identifier = event_data[:bag_id]
      bags = @db.from(:bag)
      bag = bags.first(identifier: bag_identifier)

      status_events = @db.from(:status_event)
      status_events.insert(
        bag_id: bag[:id],
        status_id: status_id,
        timestamp: event_data[:timestamp],
        note: event_data[:note]
      )
    end

    def convert_to_struct(data)
      StatusEvent.new(
        id: data[:status_event_id],
        bag_id: data[:bag_identifier],
        status: data[:status_name],
        timestamp: data[:status_event_timestamp],
        note: data[:status_event_note]
      )
    end
    private :convert_to_struct

    def base_dataset
      @db.from(:status_event)
        .join(:bag, id: :bag_id)
        .join(:status, id: Sequel[:status_event][:status_id])
        .select(
          Sequel[:status_event][:id].as(:status_event_id),
          Sequel[:status_event][:timestamp].as(:status_event_timestamp),
          Sequel[:status_event][:note].as(:status_event_note),
          Sequel[:status][:name].as(:status_name),
          Sequel[:bag][:identifier].as(:bag_identifier)
        )
    end
    private :base_dataset

    def get_all
      status_events = base_dataset.all
      status_events.map { |se| convert_to_struct(se) }
    end

    def get_all_for_bag_id(id)
      status_events = base_dataset.where(identifier: id).all
      status_events.map { |se| convert_to_struct(se) }
    end
  end
end
