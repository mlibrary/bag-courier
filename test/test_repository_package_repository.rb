require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/bag_repository"
require_relative "../lib/repository_package_repository"

module RepositoryPackageRepositorySharedTest
  def create_repository_packages(timestamp)
    1.upto(3) do |i|
      mixin_repo.create(
        identifier: "00000#{i}",
        repository_name: "fakerepository",
        updated_at: timestamp + i
      )
    end
  end

  def test_get_by_identifier
    timestamp = Time.now.utc.floor(6)
    create_repository_packages(timestamp)
    package = mixin_repo.get_by_identifier("000002")
    assert package
    assert_equal "000002", package.identifier
    assert_equal "fakerepository", package.repository_name
    assert_equal timestamp + 2, package.updated_at
  end

  def test_get_all
    create_repository_packages(Time.now.utc.floor(6))
    packages = mixin_repo.get_all
    assert_equal 3, packages.size
    assert packages.all? { |package| package.is_a?(RepositoryPackageRepository::RepositoryPackage) }

    assert_equal ["000001", "000002", "000003"], packages.map { |package| package.identifier }
    assert_equal ["fakerepository"], packages.map { |package| package.repository_name }.uniq
  end

  def test_get_max_updated_at_for_repository
    timestamp = Time.utc(2024, 3, 11, 12)
    mixin_repo.create(
      identifier: "000001",
      repository_name: "fakerepositoryone",
      updated_at: timestamp
    )
    mixin_repo.create(
      identifier: "000002",
      repository_name: "fakerepositorytwo",
      updated_at: timestamp + 5
    )
    mixin_repo.create(
      identifier: "000003",
      repository_name: "fakerepositoryone",
      updated_at: timestamp + 2
    )

    max_updated_at = mixin_repo.get_max_updated_at_for_repository("fakerepositoryone")
    assert_equal Time.utc(2024, 3, 11, 12, 0, 2), max_updated_at
  end

  def test_get_max_updated_at_for_repository_with_no_objects
    assert_nil mixin_repo.get_max_updated_at_for_repository("repository-1")
  end
end

class RepositoryPackageInMemoryRepositoryTest < Minitest::Test
  include RepositoryPackageRepositorySharedTest

  def setup
    @repo = RepositoryPackageRepository::RepositoryPackageInMemoryRepository.new
    @package_identifier = "000001"
    @repository_name = "fakerepository"
  end

  def mixin_repo
    @repo
  end

  def test_create
    timestamp = Time.now.utc
    @repo.create(
      identifier: @package_identifier,
      repository_name: @repository_name,
      updated_at: timestamp
    )
    expected = [
      RepositoryPackageRepository::RepositoryPackage.new(
        id: 0,
        identifier: @package_identifier,
        repository_name: @repository_name,
        updated_at: timestamp
      )
    ]
    assert_equal expected, @repo.repository_packages
  end

  def test_update_updated_at
    timestamp = Time.now.utc
    @repo.create(
      identifier: @package_identifier,
      repository_name: @repository_name,
      updated_at: timestamp
    )

    new_timestamp = timestamp + 5
    @repo.update_updated_at(identifier: @package_identifier, updated_at: new_timestamp)

    assert @repo.repository_packages.size == 1
    assert_equal new_timestamp, @repo.repository_packages.first.updated_at
  end

  def test_updated_at_with_nonexistent_identifier
    assert_raises RepositoryPackageRepository::RepositoryPackageRepositoryError do
      @repo.update_updated_at(identifier: @package_identifier, updated_at: Time.now.utc)
    end
  end
end

class RepositoryPackageDatabaseRepositoryTest < SequelTestCase
  include RepositoryPackageRepositorySharedTest

  def setup
    @repo = RepositoryPackageRepository::RepositoryPackageDatabaseRepository.new
    @package_identifier = "000001"
    @repository_name = "fakerepository"
  end

  def mixin_repo
    @repo
  end

  def test_create
    timestamp = Time.now.utc.floor(6)
    @repo.create(
      identifier: @package_identifier,
      repository_name: @repository_name,
      updated_at: timestamp
    )

    package = DatabaseSchema::RepositoryPackage.eager(:repository).first
    assert package
    assert_equal @package_identifier, package.identifier
    assert_equal @repository_name, package.repository.name
    assert_equal timestamp, package.updated_at
  end

  def test_updated_at
    timestamp = Time.now.utc.floor(6)
    @repo.create(
      identifier: @package_identifier,
      repository_name: @repository_name,
      updated_at: timestamp
    )

    new_timestamp = timestamp + 5
    @repo.update_updated_at(identifier: @package_identifier, updated_at: new_timestamp)
    package = DatabaseSchema::RepositoryPackage.eager(:repository).first
    assert package
    assert_equal new_timestamp, package.updated_at
  end
end

class RepositoryPackageRepositoryFactoryTest < Minitest::Test
  def test_for_creates_db_repo
    db = Sequel.connect("mock://mysql2")
    repo = RepositoryPackageRepository::RepositoryPackageRepositoryFactory.for(use_db: db)
    assert repo.is_a?(RepositoryPackageRepository::RepositoryPackageDatabaseRepository)
  end

  def test_for_creates_in_memory_repo
    repo = RepositoryPackageRepository::RepositoryPackageRepositoryFactory.for(use_db: nil)
    assert repo.is_a?(RepositoryPackageRepository::RepositoryPackageInMemoryRepository)
  end
end
