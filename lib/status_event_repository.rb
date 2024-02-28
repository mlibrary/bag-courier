require "semantic_logger"
require "sequel"

Sequel.default_timezone = :utc

module StatusEventRepository
  class UnknownStatusError < StandardError
  end

  class StatusEventRepositoryError < StandardError
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
    :bag_identifier,
    :status,
    :timestamp,
    :note,
    keyword_init: true
  )

  class StatusEventRepositoryBase
    def create(bag_identifier:, status:, timestamp:, note: nil)
      raise NotImplementedError
    end

    def get_all
      raise NotImplementedError
    end

    def get_all_for_bag_identifier(identifier)
      raise NotImplementedError
    end
  end

  class StatusEventInMemoryRepository < StatusEventRepositoryBase
    attr_reader :status_events

    def initialize
      @id = 0
      @status_events = []
    end

    def get_next_id!
      id = @id
      @id += 1
      id
    end
    private :get_next_id!

    def create(bag_identifier:, status:, timestamp:, note: nil)
      if !STATUSES.include?(status)
        raise UnknownStatusError
      end
      event = StatusEvent.new(
        id: get_next_id!,
        bag_identifier: bag_identifier,
        status: status,
        timestamp: timestamp,
        note: note
      )
      @status_events << event
    end

    def get_by_id(id)
      @status_events.find { |e| e.id == id }
    end

    def get_all
      @status_events
    end

    def get_all_for_bag_identifier(identifier)
      @status_events.select { |e| e.bag_identifier == identifier }
    end
  end

  class StatusEventDatabaseRepository
    include SemanticLogger::Loggable

    def initialize(db)
      @db = db
    end

    def create_status_if_needed(status_name)
      statuses = @db.from(:status)
      matching_status = statuses.first(name: status_name)
      if matching_status
        matching_status[:id]
      else
        statuses.insert(name: status_name)
      end
    end
    private :create_status_if_needed

    def create(bag_identifier:, status:, timestamp:, note: nil)
      if !STATUSES.include?(status)
        raise UnknownStatusError
      end
      status_id = create_status_if_needed(status)

      bags = @db.from(:bag)
      bag = bags.first(identifier: bag_identifier)
      if !bag
        raise StatusEventRepositoryError, "Bag with #{bag_identifier} does not exist."
      end
      bag_id = bag[:id]

      status_events = @db.from(:status_event)
      status_events.insert(
        bag_id: bag_id,
        status_id: status_id,
        timestamp: timestamp,
        note: note
      )
    end

    def convert_to_struct(data)
      StatusEvent.new(
        id: data[:status_event_id],
        bag_identifier: data[:bag_identifier],
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

    def get_all_for_bag_identifier(identifier)
      status_events = base_dataset.where(identifier: identifier).all
      status_events.map { |se| convert_to_struct(se) }
    end
  end

  class StatusEventRepositoryFactory
    def self.for(db)
      db ? StatusEventDatabaseRepository.new(db) : StatusEventInMemoryRepository.new
    end
  end
end
