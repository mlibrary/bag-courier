require "sequel"

module DatabaseSchema
  class Bag < Sequel::Model(:bag)
    one_to_many :status_events
  end

  class Status < Sequel::Model(:status)
    one_to_many :status_events
  end

  class StatusEvent < Sequel::Model(:status_event)
    many_to_one :status
    many_to_one :bag
  end
end
