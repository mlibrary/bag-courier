require_relative "../db/database_schema" if DB
require_relative "../services"

module BagRepository
  Bag = Struct.new(
    "Bag",
    :id,
    :identifier,
    :group_part,
    :repository_package_identifier,
    keyword_init: true
  )

  class BagRepositoryError < StandardError
  end

  class BagRepositoryBase
    def create(identifier:, group_part:, repository_package_identifier:)
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
    include DarkBlueLogger

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

    def create(identifier:, group_part:, repository_package_identifier:)
      matching_bag = @bags.find { |b| b.identifier == identifier }
      if matching_bag
        logger.info("Bag with identifier #{identifier} already exists; creation skipped")
        return
      end

      bag = Bag.new(
        id: get_next_id!,
        identifier: identifier,
        group_part: group_part,
        repository_package_identifier: repository_package_identifier
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
    include DarkBlueLogger

    def create(identifier:, group_part:, repository_package_identifier:)
      package = DatabaseSchema::RepositoryPackage.find(identifier: repository_package_identifier)
      if !package
        raise BagRepositoryError, "No RepositoryPackage with identifier #{repository_package_identifier} found."
      end

      begin
        DatabaseSchema::Bag.create(
          identifier: identifier,
          group_part: group_part,
          repository_package: package
        )
      rescue Sequel::UniqueConstraintViolation
        logger.info("Bag with identifier #{identifier} already exists; creation skipped")
      end
    end

    def convert_to_struct(bag)
      Bag.new(
        id: bag.id,
        identifier: bag.identifier,
        group_part: bag.group_part,
        repository_package_identifier: bag.repository_package.identifier
      )
    end
    private :convert_to_struct

    def base_query
      DatabaseSchema::Bag.eager(:repository_package)
    end

    def get_by_identifier(identifier)
      bag = base_query.first(identifier: identifier)
      bag && convert_to_struct(bag)
    end

    def get_all
      base_query.all.map { |bag| convert_to_struct(bag) }
    end
  end

  class BagRepositoryFactory
    def self.for(use_db:)
      use_db ? BagDatabaseRepository.new : BagInMemoryRepository.new
    end
  end
end
