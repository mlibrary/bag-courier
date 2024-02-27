require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "test_helper"
require_relative "../lib/bag_repository"

module BagRepositorySharedTest
  def test_get_by_identifier
    mixin_repo.create(identifier: mixin_bag_id, group_part: 2)
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
      mixin_repo.create(
        identifier: "repository.context-00#{i}",
        group_part: 1
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
    @bag_id = "repository.context-001"
    @repo = BagRepository::BagInMemoryRepository.new
  end

  def mixin_bag_id
    @bag_id
  end

  def mixin_repo
    @repo
  end

  def test_create
    @repo.create(identifier: @bag_id, group_part: 2)
    assert_equal [BagRepository::Bag.new(id: 0, identifier: @bag_id, group_part: 2)], @repo.bags
  end

  def test_create_when_already_exists
    messages = semantic_logger_events do
      @repo.create(identifier: @bag_id, group_part: 2)
      @repo.create(identifier: @bag_id, group_part: 2)
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
    @bag_id = "repository.context-001"
    @repo = BagRepository::BagDatabaseRepository.new(DB)
  end

  def mixin_bag_id
    @bag_id
  end

  def mixin_repo
    @repo
  end

  def test_create
    @repo.create(identifier: @bag_id, group_part: 2)
    bags = DB.from(:bag)
    bag = bags.first(identifier: @bag_id)
    assert bag
    assert_equal @bag_id, bag[:identifier]
    assert_equal 2, bag[:group_part]
  end

  def test_create_when_already_exists
    messages = semantic_logger_events do
      @repo.create(identifier: @bag_id, group_part: 2)
      @repo.create(identifier: @bag_id, group_part: 2)
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
    repo = BagRepository::BagRepositoryFactory.for(db)
    assert repo.is_a?(BagRepository::BagDatabaseRepository)
  end

  def test_for_creates_in_memory_repo
    repo = BagRepository::BagRepositoryFactory.for(nil)
    assert repo.is_a?(BagRepository::BagInMemoryRepository)
  end
end
