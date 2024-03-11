require "semantic_logger"

require_relative "../db/database_schema" if DB

module DigitalObjectRepository
  DigitalObject = Struct.new(
    "DigitalObject",
    :id,
    :identifier,
    :system_name,
    :updated_at,
    keyword_init: true
  )

  class DigitalObjectRepositoryError < StandardError
  end

  class DigitalObjectRepositoryBase
    def create(identifier:, system_name:, updated_at:)
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

    def get_max_updated_at_for_system(system_name)
      raise NotImplementedError
    end
  end

  class DigitalObjectInMemoryRepository < DigitalObjectRepositoryBase
    include SemanticLogger::Loggable

    attr_reader :digital_objects

    def initialize
      @id = 0
      @digital_objects = []
    end

    def get_next_id!
      id = @id
      @id += 1
      id
    end
    private :get_next_id!

    def create(identifier:, system_name:, updated_at:)
      matching_dobj = @digital_objects.find { |dobj| dobj.identifier == identifier }
      if matching_dobj
        logger.info("DigitalObject with identifier #{identifier} already exists; creation skipped")
        return false
      end

      dobj = DigitalObject.new(
        id: get_next_id!,
        identifier: identifier,
        updated_at: updated_at,
        system_name: system_name
      )
      @digital_objects << dobj
      true
    end

    def get_by_identifier(identifier)
      @digital_objects.find { |dobj| dobj.identifier == identifier }
    end

    def get_all
      @digital_objects
    end

    def update_updated_at(identifier:, updated_at:)
      dobj = get_by_identifier(identifier)
      if !dobj
        raise DigitalObjectRepositoryError, "No DigitalObject with identifier #{identifier} was found."
      end

      dobj.updated_at = updated_at
    end

    def get_max_updated_at_for_system(system_name)
      max_obj = @digital_objects.select { |dobj| dobj.system_name == system_name }
        .max_by(&:updated_at)
      max_obj&.updated_at
    end
  end

  class DigitalObjectDatabaseRepository < DigitalObjectRepositoryBase
    include SemanticLogger::Loggable

    def create(identifier:, system_name:, updated_at:)
      system = DatabaseSchema::System.find_or_create(name: system_name)

      dobj = DatabaseSchema::DigitalObject.new(
        identifier: identifier,
        updated_at: updated_at
      )
      dobj.system = system
      dobj.save
      true
    rescue Sequel::UniqueConstraintViolation
      logger.info(
        "DigitalObject with identifier #{identifier} already exists; creation skipped."
      )
      false
    end

    def update_updated_at(identifier:, updated_at:)
      dobj = DatabaseSchema::DigitalObject.find(identifier: identifier)
      dobj.updated_at = updated_at
      dobj.save
    end

    def convert_to_struct(dobj)
      DigitalObject.new(
        id: dobj.id,
        identifier: dobj.identifier,
        updated_at: dobj.updated_at,
        system_name: dobj.system.name
      )
    end
    private :convert_to_struct

    def base_query
      DatabaseSchema::DigitalObject.eager(:system)
    end

    def get_by_identifier(identifier)
      dobj = base_query.first(identifier: identifier)
      dobj && convert_to_struct(dobj)
    end

    def get_all
      base_query.all.map { |dobj| convert_to_struct(dobj) }
    end

    def get_max_updated_at_for_system(system_name)
      base_query.where(system: DatabaseSchema::System.where(name: system_name))
        .max(:updated_at)
    end
  end

  class DigitalObjectRepositoryFactory
    def self.for(use_db:)
      use_db ? DigitalObjectDatabaseRepository.new : DigitalObjectInMemoryRepository.new
    end
  end
end
