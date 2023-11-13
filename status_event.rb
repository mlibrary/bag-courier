module StatusEvent
  class UnknownStatusError < StandardError
  end

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
      deposit_skipped deposited depositing
      copied copying
      failed
      packed packing
      skipped
      uploaded uploading
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
      @status_events << event_data.merge({id: get_next_id!})
    end

    def get_by_id(id)
      @status_events.find { |e| e[:id] == id }
    end

    def get_all_by_work_id(work_id)
      @status_events.select { |e| e[:work_id] == work_id }
    end
  end
end
