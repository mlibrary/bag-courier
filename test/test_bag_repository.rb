require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../lib/bag_repository"

module BagRepositorySharedTest
  def test_get_by_identifier
    mixin_repo.create(identifier: mixin_bag_id, group_part: 2)

    bag = mixin_repo.get_by_identifier(mixin_bag_id)
    assert bag.is_a?(BagRepository::Bag)
    assert_equal bag.identifier, mixin_bag_id
    assert_equal bag.group_part, 2
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
end
