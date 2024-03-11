require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "test_helper"
require_relative "../db/database_schema"
require_relative "../lib/bag_repository"
require_relative "../lib/digital_object_repository"

module BagRepositorySharedTest
  def test_get_by_identifier
    mixin_dobj_repo.create(identifier: mixin_dobj_identifier, system_name: mixin_system_name, updated_at: Time.now.utc)
    mixin_repo.create(identifier: mixin_bag_id, group_part: 2, digital_object_identifier: mixin_dobj_identifier)
    bag = mixin_repo.get_by_identifier(mixin_bag_id)
    assert bag.is_a?(BagRepository::Bag)
    assert_equal bag.identifier, mixin_bag_id
    assert_equal bag.group_part, 2
  end

  def test_get_by_identifier_finds_nothing
    result = mixin_repo.get_by_identifier("repository.context-200")
    assert_nil result
  end

  def test_get_all
    1.upto(5) do |i|
      mixin_dobj_repo.create(
        identifier: "00000#{i}",
        system_name: mixin_system_name,
        updated_at: Time.now.utc
      )
      mixin_repo.create(
        identifier: "repository.context-00#{i}",
        group_part: 1,
        digital_object_identifier: "00000#{i}"
      )
    end
    bags = mixin_repo.get_all
    assert_equal 5, bags.size
    assert bags.all? { |b| b.is_a?(BagRepository::Bag) }
    bag_ids = bags.map { |b| b.id }
    assert_equal bag_ids, bag_ids.uniq
  end
end

class BagInMemoryRepositioryTest < Minitest::Test
  include BagRepositorySharedTest

  def setup
    @dobj_identifier = "00001"
    @system_name = "repository-1"
    @dobj_repo = DigitalObjectRepository::DigitalObjectInMemoryRepository.new

    @bag_id = "repository.context-001"
    @repo = BagRepository::BagInMemoryRepository.new
  end

  def mixin_bag_id
    @bag_id
  end

  def mixin_repo
    @repo
  end

  def mixin_dobj_repo
    @dobj_repo
  end

  def mixin_dobj_identifier
    @dobj_identifier
  end

  def mixin_system_name
    @system_name
  end

  def test_create
    @repo.create(identifier: @bag_id, group_part: 2, digital_object_identifier: @dobj_identifier)
    expected = [BagRepository::Bag.new(
      id: 0, identifier: @bag_id, group_part: 2, digital_object_identifier: @dobj_identifier
    )]
    assert_equal expected, @repo.bags
  end

  def test_create_when_already_exists
    messages = semantic_logger_events do
      @repo.create(identifier: @bag_id, group_part: 2, digital_object_identifier: @dobj_identifier)
      @repo.create(identifier: @bag_id, group_part: 2, digital_object_identifier: @dobj_identifier)
    end
    bags = @repo.bags
    assert_equal 1, bags.size
    assert_equal 1, messages.size
    assert_semantic_logger_event(
      messages[0],
      level: :info,
      message: "Bag with identifier repository.context-001 already exists; creation skipped"
    )
  end
end

class BagDatabaseRepositoryTest < SequelTestCase
  include BagRepositorySharedTest

  def setup
    @dobj_identifier = "00001"
    @system_name = "repository-1"
    @dobj_repo = DigitalObjectRepository::DigitalObjectDatabaseRepository.new

    @bag_id = "repository.context-001"
    @repo = BagRepository::BagDatabaseRepository.new
  end

  def mixin_bag_id
    @bag_id
  end

  def mixin_repo
    @repo
  end

  def mixin_dobj_repo
    @dobj_repo
  end

  def mixin_dobj_identifier
    @dobj_identifier
  end

  def mixin_system_name
    @system_name
  end

  def create_digital_object
    @dobj_repo.create(
      identifier: @dobj_identifier,
      system_name: @system_name,
      updated_at: Time.now.utc
    )
  end

  def test_create
    create_digital_object

    @repo.create(
      identifier: @bag_id,
      group_part: 2,
      digital_object_identifier: @dobj_identifier
    )
    bag = DatabaseSchema::Bag.eager(:digital_object).first

    assert bag
    assert_equal @bag_id, bag[:identifier]
    assert_equal 2, bag[:group_part]
    assert_equal @dobj_identifier, bag.digital_object.identifier
  end

  def test_create_without_digital_object
    assert_raises BagRepository::BagRepositoryError do
      @repo.create(
        identifier: @bag_id,
        group_part: 2,
        digital_object_identifier: "nonexistent-id"
      )
    end
  end

  def test_create_when_already_exists
    create_digital_object

    messages = semantic_logger_events do
      @repo.create(identifier: @bag_id, group_part: 2, digital_object_identifier: @dobj_identifier)
      @repo.create(identifier: @bag_id, group_part: 2, digital_object_identifier: @dobj_identifier)
    end
    bags = DB.from(:bag).all
    assert_equal 1, bags.size
    assert_equal 1, messages.size
    assert_semantic_logger_event(
      messages[0],
      level: :info,
      message: "Bag with identifier repository.context-001 already exists; creation skipped"
    )
  end
end

class BagRepositoryFactoryTest < Minitest::Test
  def test_for_creates_db_repo
    db = Sequel.connect("mock://mysql2")
    repo = BagRepository::BagRepositoryFactory.for(use_db: db)
    assert repo.is_a?(BagRepository::BagDatabaseRepository)
  end

  def test_for_creates_in_memory_repo
    repo = BagRepository::BagRepositoryFactory.for(use_db: nil)
    assert repo.is_a?(BagRepository::BagInMemoryRepository)
  end
end
