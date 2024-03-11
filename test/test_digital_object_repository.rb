require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/digital_object_repository"
require_relative "../lib/bag_repository"

module DigitalObjectRepositorySharedTest
  def create_digital_objects(timestamp)
    1.upto(3) do |i|
      mixin_repo.create(
        identifier: "00000#{i}",
        system_name: mixin_system_name,
        updated_at: timestamp + i
      )
    end
  end

  def test_get_by_identifier
    timestamp = Time.now.utc.floor(6)
    create_digital_objects(timestamp)
    dobj = mixin_repo.get_by_identifier("000002")
    assert dobj
    assert_equal "000002", dobj.identifier
    assert_equal "repository-1", dobj.system_name
    assert_equal timestamp + 2, dobj.updated_at
  end

  def test_get_all
    create_digital_objects(Time.now.utc.floor(6))
    dobjs = mixin_repo.get_all
    assert_equal 3, dobjs.size
    assert dobjs.all? { |dobj| dobj.is_a?(DigitalObjectRepository::DigitalObject) }

    assert_equal ["000001", "000002", "000003"], dobjs.map { |dobj| dobj.identifier }
    assert_equal ["repository-1"], dobjs.map { |dobj| dobj.system_name }.uniq
  end
end

class DigitalObjectInMemoryRepositoryTest < Minitest::Test
  include DigitalObjectRepositorySharedTest

  def setup
    @dobj_identifier = "000001"
    @system_name = "repository-1"
    @repo = DigitalObjectRepository::DigitalObjectInMemoryRepository.new
  end

  def mixin_repo
    @repo
  end

  def mixin_dobj_identifier
    @dobj_identifier
  end

  def mixin_system_name
    @system_name
  end

  def test_create
    timestamp = Time.now.utc
    @repo.create(
      identifier: @dobj_identifier,
      system_name: @system_name,
      updated_at: timestamp
    )
    expected = [
      DigitalObjectRepository::DigitalObject.new(
        id: 0,
        identifier: @dobj_identifier,
        system_name: @system_name,
        updated_at: timestamp
      )
    ]
    assert_equal expected, @repo.digital_objects
  end

  def test_update_updated_at
    timestamp = Time.now.utc
    @repo.create(
      identifier: @dobj_identifier,
      system_name: @system_name,
      updated_at: timestamp
    )

    new_timestamp = timestamp + 5
    @repo.update_updated_at(identifier: @dobj_identifier, updated_at: new_timestamp)

    assert @repo.digital_objects.size == 1
    assert_equal new_timestamp, @repo.digital_objects.first.updated_at
  end

  def test_updated_at_with_nonexistent_identifier
    assert_raises DigitalObjectRepository::DigitalObjectRepositoryError do
      @repo.update_updated_at(identifier: @dobj_identifier, updated_at: Time.now.utc)
    end
  end
end

class DigitalObjectDatabaseRepositoryTest < SequelTestCase
  include DigitalObjectRepositorySharedTest

  def setup
    @dobj_identifier = "000001"
    @system_name = "repository-1"
    @repo = DigitalObjectRepository::DigitalObjectDatabaseRepository.new
  end

  def mixin_repo
    @repo
  end

  def mixin_dobj_identifier
    @dobj_identifier
  end

  def mixin_system_name
    @system_name
  end

  def test_create
    timestamp = Time.now.utc.floor(6)
    @repo.create(
      identifier: @dobj_identifier,
      system_name: @system_name,
      updated_at: timestamp
    )

    dobj = DatabaseSchema::DigitalObject.eager(:system).first
    assert dobj
    assert_equal @dobj_identifier, dobj.identifier
    assert_equal @system_name, dobj.system.name
    assert_equal timestamp, dobj.updated_at
  end

  def test_updated_at
    timestamp = Time.now.utc.floor(6)
    @repo.create(
      identifier: @dobj_identifier,
      system_name: @system_name,
      updated_at: timestamp
    )

    new_timestamp = timestamp + 5
    @repo.update_updated_at(identifier: @dobj_identifier, updated_at: new_timestamp)
    dobj = DatabaseSchema::DigitalObject.eager(:system).first
    assert dobj
    assert_equal new_timestamp, dobj.updated_at
  end
end

class DigitalObjectRepositoryFactoryTest < Minitest::Test
  def test_for_creates_db_repo
    db = Sequel.connect("mock://mysql2")
    repo = DigitalObjectRepository::DigitalObjectRepositoryFactory.for(use_db: db)
    assert repo.is_a?(DigitalObjectRepository::DigitalObjectDatabaseRepository)
  end

  def test_for_creates_in_memory_repo
    repo = DigitalObjectRepository::DigitalObjectRepositoryFactory.for(use_db: nil)
    assert repo.is_a?(DigitalObjectRepository::DigitalObjectInMemoryRepository)
  end
end
