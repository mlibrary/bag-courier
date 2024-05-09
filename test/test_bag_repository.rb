require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "test_helper"
require_relative "../db/database_schema"
require_relative "../lib/bag_repository"
require_relative "../lib/repository_package_repository"

module BagRepositorySharedTest
  def test_get_by_identifier
    mixin_package_repo.create(
      identifier: mixin_package_identifier, repository_name: mixin_repository_name, updated_at: Time.now.utc
    )
    mixin_repo.create(
      identifier: mixin_bag_id, group_part: 2, repository_package_identifier: mixin_package_identifier
    )
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
      mixin_package_repo.create(
        identifier: "00000#{i}",
        repository_name: mixin_repository_name,
        updated_at: Time.now.utc
      )
      mixin_repo.create(
        identifier: "repository.context-00#{i}",
        group_part: 1,
        repository_package_identifier: "00000#{i}"
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

    @package_repo = RepositoryPackageRepository::RepositoryPackageInMemoryRepository.new
    @package_identifier = "00001"
    @repository_name = "repository-1"
  end

  def mixin_repo
    @repo
  end

  def mixin_bag_id
    @bag_id
  end

  def mixin_package_repo
    @package_repo
  end

  def mixin_package_identifier
    @package_identifier
  end

  def mixin_repository_name
    @repository_name
  end

  def test_create
    @repo.create(identifier: @bag_id, group_part: 2, repository_package_identifier: @package_identifier)
    expected = [BagRepository::Bag.new(
      id: 0, identifier: @bag_id, group_part: 2, repository_package_identifier: @package_identifier
    )]
    assert_equal expected, @repo.bags
  end

  def test_create_when_already_exists
    @package_repo.create(
      identifier: @package_identifier,
      repository_name: @repository_name,
      updated_at: Time.now.utc
    )
    messages = semantic_logger_events do
      @repo.create(identifier: @bag_id, group_part: 2, repository_package_identifier: @package_identifier)
      @repo.create(identifier: @bag_id, group_part: 2, repository_package_identifier: @package_identifier)
    end
    bags = @repo.bags
    assert_equal 1, bags.size
    assert_equal 1, messages.size
    assert_semantic_logger_event(
      messages[0],
      level: :debug,
      message: "Bag with identifier repository.context-001 already exists; creation skipped"
    )
  end
end

class BagDatabaseRepositoryTest < SequelTestCase
  include BagRepositorySharedTest

  def setup
    @repo = BagRepository::BagDatabaseRepository.new
    @bag_id = "repository.context-001"

    @package_repo = RepositoryPackageRepository::RepositoryPackageDatabaseRepository.new
    @package_identifier = "00001"
    @repository_name = "repository-1"
  end

  def mixin_repo
    @repo
  end

  def mixin_bag_id
    @bag_id
  end

  def mixin_package_repo
    @package_repo
  end

  def mixin_package_identifier
    @package_identifier
  end

  def mixin_repository_name
    @repository_name
  end

  def create_repository_package
    @package_repo.create(
      identifier: @package_identifier,
      repository_name: @repository_name,
      updated_at: Time.now.utc
    )
  end

  def test_create
    create_repository_package

    @repo.create(
      identifier: @bag_id,
      group_part: 2,
      repository_package_identifier: @package_identifier
    )
    bag = DatabaseSchema::Bag.eager(:repository_package).first

    assert bag
    assert_equal @bag_id, bag.identifier
    assert_equal 2, bag.group_part
    assert_equal @package_identifier, bag.repository_package.identifier
  end

  def test_create_without_repository_package
    assert_raises BagRepository::BagRepositoryError do
      @repo.create(
        identifier: @bag_id,
        group_part: 2,
        repository_package_identifier: "nonexistent-id"
      )
    end
  end

  def test_create_when_already_exists
    create_repository_package

    messages = semantic_logger_events do
      @repo.create(identifier: @bag_id, group_part: 2, repository_package_identifier: @package_identifier)
      @repo.create(identifier: @bag_id, group_part: 2, repository_package_identifier: @package_identifier)
    end
    bags = DatabaseSchema::Bag.eager(:repository_package).all
    assert_equal 1, bags.size
    assert_equal 1, messages.size
    assert_semantic_logger_event(
      messages[0],
      level: :debug,
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
