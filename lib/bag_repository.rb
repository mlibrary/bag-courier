module BagRepository
  Bag = Struct.new(
    "Bag",
    :id,
    :identifier,
    :group_part,
    keyword_init: true
  )

  class BagRepositoryBase
    def create(identifier:, group_part:)
      raise NotImplementedError
    end

    def get_by_identifier(identifier)
      raise NotImplementedError
    end

    def get_all
      raise NotImplementedError
    end
  end

  class BagInMemoryRepository < BagRepositoryBase
    attr_reader :bags

    def initialize
      @id = 0
      @bags = []
    end

    def get_next_id!
      id = @id
      @id += 1
      id
    end
    private :get_next_id!

    def create(identifier:, group_part:)
      bag = Bag.new(
        id: get_next_id!,
        identifier: identifier,
        group_part: group_part
      )
      @bags << bag
    end

    def get_by_identifier(identifier)
      @bags.find { |b| b.identifier == identifier }
    end

    def get_all
      @bags
    end
  end

  class BagDatabaseRepository < BagRepositoryBase
    def initialize(db)
      @db = db
    end

    def create(identifier:, group_part:)
      bags = @db.from(:bag)
      matching_bag = bags.first(identifier: identifier)
      if matching_bag
        logger.debug("Bag with identifier #{identifier} already exists: #{matching_bag}")
      else
        bags.insert(identifier: identifier, group_part: group_part)
      end
    end

    def get_by_identifier(identifier)
      bag_data = @db.from(:bag).first(identifier: identifier)
      Bag.new(
        id: bag_data[:id],
        identifier: bag_data[:identifier],
        group_part: bag_data[:group_part]
      )
    end

    def get_all
      @db.from(:bag).map do |bag_data|
        Bag.new(
          id: bag_data[:id],
          identifier: bag_data[:identifier],
          group_part: bag_data[:group_part]
        )
      end
    end
  end
end
