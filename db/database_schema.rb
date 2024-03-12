require "sequel"

module DatabaseSchema
  class Repository < Sequel::Model(:repository)
    one_to_many :repository_packages
  end

  class RepositoryPackage < Sequel::Model(:repository_package)
    many_to_one :repository
    one_to_many :bags
  end

  class Bag < Sequel::Model(:bag)
    one_to_many :status_events
    many_to_one :repository_package
  end

  class Status < Sequel::Model(:status)
    one_to_many :status_events
  end

  class StatusEvent < Sequel::Model(:status_event)
    many_to_one :status
    many_to_one :bag
  end
end
