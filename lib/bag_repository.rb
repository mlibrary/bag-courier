require "semantic_logger"

require_relative "../db/database_schema" if DB

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
    include SemanticLogger::Loggable

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
      matching_bag = @bags.find { |b| b.identifier == identifier }
      if matching_bag
        logger.info("Bag with identifier #{identifier} already exists; creation skipped")
        return
      end

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
    include SemanticLogger::Loggable

    def create(identifier:, group_part:)
      DatabaseSchema::Bag.create(identifier: identifier, group_part: group_part)
    rescue Sequel::UniqueConstraintViolation
      logger.info("Bag with identifier #{identifier} already exists; creation skipped")
    end

    def convert_to_struct(bag)
      Bag.new(
        id: bag.id,
        identifier: bag.identifier,
        group_part: bag.group_part
      )
    end
    private :convert_to_struct

    def get_by_identifier(identifier)
      bag = DatabaseSchema::Bag.first(identifier: identifier)
      bag && convert_to_struct(bag)
    end

    def get_all
      DatabaseSchema::Bag.map { |bag| convert_to_struct(bag) }
    end
  end

  class BagRepositoryFactory
    def self.for(db)
      db ? BagDatabaseRepository.new : BagInMemoryRepository.new
    end
  end
end
