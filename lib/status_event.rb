module StatusEvent
  class UnknownStatusError < StandardError
  end

  StatusEvent = Struct.new(:id, :object_id, :bag_id, :status, :timestamp, keyword_init: true)

  class StatusEventRepositoryBase
    def initialize(status_events = nil)
      raise NotImplementedError
    end

    def create(event_data)
      raise NotImplementedError
    end

    def get_by_id(id)
      raise NotImplementedError
    end

    def get_all_by_work_id(id)
      raise NotImplementedError
    end
  end

  class StatusEventInMemoryRepository < StatusEventRepositoryBase
    STATUSES = %w[
      bagged bagging
      delivery_skipped delivered delivering
      copied copying
      failed
      packed packing
      skipped
      sent sending
    ]

    def initialize(status_events = nil)
      @id = 0
      @status_events = status_events.nil? ? [] : status_events
    end

    def get_next_id!
      id = @id
      @id += 1
      id
    end

    def create(event_data)
      if !STATUSES.include?(event_data[:status])
        raise UnknownStatusError
      end
      event = StatusEvent.new(
        id: get_next_id!,
        bag_id: event_data[:bag_id],
        object_id: event_data[:object_id],
        status: event_data[:status],
        timestamp: event_data[:timestamp]
      )
      @status_events << event
    end

    def get_by_id(id)
      @status_events.find { |e| e.id == id }
    end

    def get_all_by_bag_id(bag_id)
      @status_events.select { |e| e.bag_id == bag_id }
    end
  end
end
