require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../lib/bag_repository"
require_relative "../lib/repository_package_repository"
require_relative "../lib/status_event_repository"

module StatusEventRepositorySharedTest
  def test_create_with_unknown_status
    assert_raises(StatusEventRepository::UnknownStatusError) do
      mixin_repo.create(
        bag_identifier: mixin_bag_identifier,
        status: "turned_inside_out",
        timestamp: Time.now.utc
      )
    end
  end

  def test_get_all
    mixin_package_repo.create(
      identifier: mixin_package_identifier,
      repository_name: "repository-1",
      updated_at: Time.now.utc
    )
    mixin_bag_repo.create(
      identifier: mixin_bag_identifier,
      group_part: 1,
      repository_package_identifier: mixin_package_identifier
    )
    ["bagging", "copying", "copied", "bagged"].each do |status|
      mixin_repo.create(
        status: status,
        bag_identifier: mixin_bag_identifier,
        timestamp: Time.now.utc
      )
    end
    status_events = mixin_repo.get_all
    assert_equal 4, status_events.size
    assert status_events.all? { |s| s.is_a?(StatusEventRepository::StatusEvent) }
    event_ids = status_events.map { |se| se.id }
    assert_equal event_ids, event_ids.uniq
    expected = [
      {status: "bagging", bag_identifier: mixin_bag_identifier},
      {status: "copying", bag_identifier: mixin_bag_identifier},
      {status: "copied", bag_identifier: mixin_bag_identifier},
      {status: "bagged", bag_identifier: mixin_bag_identifier}
    ]
    assert_equal(
      expected,
      status_events.map { |se| {status: se.status, bag_identifier: se.bag_identifier} }
    )
  end

  def test_get_all_for_bag_identifier
    second_package_identifier = "000002"
    mixin_package_repo.create(identifier: mixin_package_identifier, repository_name: "repository-1", updated_at: Time.now.utc)
    mixin_package_repo.create(identifier: second_package_identifier, repository_name: "repository-1", updated_at: Time.now.utc)

    bag_identifier_one = mixin_bag_identifier
    bag_identifier_two = "repository.context-002"
    mixin_bag_repo.create(identifier: bag_identifier_one, group_part: 1, repository_package_identifier: mixin_package_identifier)
    mixin_bag_repo.create(identifier: bag_identifier_two, group_part: 1, repository_package_identifier: second_package_identifier)
    mixin_repo.create(status: "bagging", bag_identifier: bag_identifier_one, timestamp: Time.now.utc)
    mixin_repo.create(status: "bagging", bag_identifier: bag_identifier_two, timestamp: Time.now.utc)
    mixin_repo.create(status: "bagged", bag_identifier: bag_identifier_two, timestamp: Time.now.utc)
    events = mixin_repo.get_all_for_bag_identifier(bag_identifier_two)
    assert events.all? { |s| s.is_a?(StatusEventRepository::StatusEvent) }
    assert_equal 2, events.length
    assert_equal ["bagging", "bagged"], events.map { |e| e.status }
  end
end

class StatusEventInMemoryRepositoryTest < Minitest::Test
  include StatusEventRepositorySharedTest
  include SemanticLogger::Loggable

  def setup
    @repo = StatusEventRepository::StatusEventInMemoryRepository.new
    @bag_repo = BagRepository::BagInMemoryRepository.new
    @bag_identifier = "repository.context-001"
    @package_repo = RepositoryPackageRepository::RepositoryPackageInMemoryRepository.new
    @package_identifier = "000001"
  end

  def mixin_bag_identifier
    @bag_identifier
  end

  def mixin_repo
    @repo
  end

  def mixin_bag_repo
    @bag_repo
  end

  def mixin_package_identifier
    @package_identifier
  end

  def mixin_package_repo
    @package_repo
  end

  def test_create
    timestamp = Time.now.utc
    @repo.create(
      status: "bagged",
      bag_identifier: @bag_identifier,
      timestamp: timestamp,
      note: "something happening here"
    )
    expected = [
      StatusEventRepository::StatusEvent.new(
        id: 0,
        status: "bagged",
        bag_identifier: @bag_identifier,
        timestamp: timestamp,
        note: "something happening here"
      )
    ]
    assert_equal expected, @repo.status_events
  end
end

class StatusEventDatabaseRepositoryTest < SequelTestCase
  include StatusEventRepositorySharedTest

  def setup
    @repo = StatusEventRepository::StatusEventDatabaseRepository.new
    @bag_repo = BagRepository::BagDatabaseRepository.new
    @bag_identifier = "repository.context-001"
    @package_repo = RepositoryPackageRepository::RepositoryPackageDatabaseRepository.new
    @package_identifier = "000001"
  end

  def mixin_bag_identifier
    @bag_identifier
  end

  def mixin_repo
    @repo
  end

  def mixin_bag_repo
    @bag_repo
  end

  def mixin_package_identifier
    @package_identifier
  end

  def mixin_package_repo
    @package_repo
  end

  def test_create
    @package_repo.create(identifier: @package_identifier, repository_name: "repository-1", updated_at: Time.now.utc)
    @bag_repo.create(identifier: @bag_identifier, group_part: 2, repository_package_identifier: @package_identifier)
    bag_db_id = @bag_repo.get_by_identifier(@bag_identifier).id
    timestamp = Time.now.utc.floor(6)  # To match database precision
    @repo.create(
      status: "bagged",
      bag_identifier: @bag_identifier,
      timestamp: timestamp,
      note: nil
    )
    status_events = DB.from(:status_event).join(:status, id: :status_id).all
    assert_equal 1, status_events.length
    status_event = status_events[0]
    assert_equal "bagged", status_event[:name]
    assert_equal bag_db_id, status_event[:bag_id]
    assert_equal timestamp, status_event[:timestamp]
  end
end

class StatusEventRepositoryFactoryTest < Minitest::Test
  def test_for_creates_db_repo
    db = Sequel.connect("mock://mysql2")
    repo = StatusEventRepository::StatusEventRepositoryFactory.for(use_db: db)
    assert repo.is_a?(StatusEventRepository::StatusEventDatabaseRepository)
  end

  def test_for_creates_in_memory_repo
    repo = StatusEventRepository::StatusEventRepositoryFactory.for(use_db: nil)
    assert repo.is_a?(StatusEventRepository::StatusEventInMemoryRepository)
  end
end
