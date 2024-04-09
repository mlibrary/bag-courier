$LOAD_PATH.unshift(File.dirname(__FILE__))
require "services"

require_relative "../db/database_schema" if DB

module RepositoryPackageRepository
  RepositoryPackage = Struct.new(
    "RepositoryPackage",
    :id,
    :identifier,
    :repository_name,
    :updated_at,
    keyword_init: true
  )

  class RepositoryPackageRepositoryError < StandardError
  end

  class RepositoryPackageRepositoryBase
    def create(identifier:, repository_name:, updated_at:)
      raise NotImplementedError
    end

    def get_by_identifier(identifier)
      raise NotImplementedError
    end

    def get_all
      raise NotImplementedError
    end

    def update_updated_at(identifier:, updated_at:)
      raise NotImplementedError
    end

    def get_max_updated_at_for_repository(repository_name)
      raise NotImplementedError
    end
  end

  class RepositoryPackageInMemoryRepository < RepositoryPackageRepositoryBase
    include DarkBlueLogger

    attr_reader :repository_packages

    def initialize
      @id = 0
      @repository_packages = []
    end

    def get_next_id!
      id = @id
      @id += 1
      id
    end
    private :get_next_id!

    def create(identifier:, repository_name:, updated_at:)
      matching_package = @repository_packages.find { |package| package.identifier == identifier }
      if matching_package
        logger.info("RepositoryPackage with identifier #{identifier} already exists; creation skipped")
        return false
      end

      package = RepositoryPackage.new(
        id: get_next_id!,
        identifier: identifier,
        updated_at: updated_at,
        repository_name: repository_name
      )
      @repository_packages << package
      true
    end

    def get_by_identifier(identifier)
      @repository_packages.find { |package| package.identifier == identifier }
    end

    def get_all
      @repository_packages
    end

    def update_updated_at(identifier:, updated_at:)
      package = get_by_identifier(identifier)
      if !package
        raise RepositoryPackageRepositoryError, "No RepositoryPackage with identifier #{identifier} was found."
      end

      package.updated_at = updated_at
    end

    def get_max_updated_at_for_repository(repository_name)
      max_package = @repository_packages.select { |package| package.repository_name == repository_name }
        .max_by(&:updated_at)
      max_package&.updated_at
    end
  end

  class RepositoryPackageDatabaseRepository < RepositoryPackageRepositoryBase
    include DarkBlueLogger

    def create(identifier:, repository_name:, updated_at:)
      repository = DatabaseSchema::Repository.find_or_create(name: repository_name)

      package = DatabaseSchema::RepositoryPackage.new(
        identifier: identifier,
        updated_at: updated_at
      )
      package.repository = repository
      package.save
      true
    rescue Sequel::UniqueConstraintViolation
      logger.info(
        "RepositoryPackage with identifier #{identifier} already exists; creation skipped."
      )
      false
    end

    def update_updated_at(identifier:, updated_at:)
      package = DatabaseSchema::RepositoryPackage.find(identifier: identifier)
      package.updated_at = updated_at
      package.save
    end

    def convert_to_struct(package)
      RepositoryPackage.new(
        id: package.id,
        identifier: package.identifier,
        updated_at: package.updated_at,
        repository_name: package.repository.name
      )
    end
    private :convert_to_struct

    def base_query
      DatabaseSchema::RepositoryPackage.eager(:repository)
    end

    def get_by_identifier(identifier)
      package = base_query.first(identifier: identifier)
      package && convert_to_struct(package)
    end

    def get_all
      base_query.all.map { |package| convert_to_struct(package) }
    end

    def get_max_updated_at_for_repository(repository_name)
      base_query.where(repository: DatabaseSchema::Repository.where(name: repository_name))
        .max(:updated_at)
    end
  end

  class RepositoryPackageRepositoryFactory
    def self.for(use_db:)
      use_db ? RepositoryPackageDatabaseRepository.new : RepositoryPackageInMemoryRepository.new
    end
  end
end
