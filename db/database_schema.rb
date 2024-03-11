require "sequel"

module DatabaseSchema
  class System < Sequel::Model(:system)
    one_to_many :digital_object
  end

  class DigitalObject < Sequel::Model(:digital_object)
    many_to_one :system
    one_to_many :bags
  end

  class Bag < Sequel::Model(:bag)
    one_to_many :status_events
    many_to_one :digital_object
  end

  class Status < Sequel::Model(:status)
    one_to_many :status_events
  end

  class StatusEvent < Sequel::Model(:status_event)
    many_to_one :status
    many_to_one :bag
  end
end
