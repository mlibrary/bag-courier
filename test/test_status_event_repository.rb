require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../db/database_schema"
require_relative "../lib/bag_repository"
require_relative "../lib/bag_status"
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
    [BagStatus::BAGGING, BagStatus::COPYING, BagStatus::COPIED, BagStatus::BAGGED].each do |status|
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
      {status: BagStatus::BAGGING, bag_identifier: mixin_bag_identifier},
      {status: BagStatus::COPYING, bag_identifier: mixin_bag_identifier},
      {status: BagStatus::COPIED, bag_identifier: mixin_bag_identifier},
      {status: BagStatus::BAGGED, bag_identifier: mixin_bag_identifier}
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
    mixin_repo.create(status: BagStatus::BAGGING, bag_identifier: bag_identifier_one, timestamp: Time.now.utc)
    mixin_repo.create(status: BagStatus::BAGGING, bag_identifier: bag_identifier_two, timestamp: Time.now.utc)
    mixin_repo.create(status: BagStatus::BAGGED, bag_identifier: bag_identifier_two, timestamp: Time.now.utc)
    events = mixin_repo.get_all_for_bag_identifier(bag_identifier_two)
    assert events.all? { |s| s.is_a?(StatusEventRepository::StatusEvent) }
    assert_equal 2, events.length
    assert_equal [BagStatus::BAGGING, BagStatus::BAGGED], events.map { |e| e.status }
  end

  def test_get_latest_event_for_bag
    second_package_identifier = "000002"
    mixin_package_repo.create(identifier: mixin_package_identifier, repository_name: "repository-1", updated_at: Time.now.utc)
    mixin_package_repo.create(identifier: second_package_identifier, repository_name: "repository-1", updated_at: Time.now.utc)

    bag_identifier_one = mixin_bag_identifier
    bag_identifier_two = "repository.context-002"
    start_time = Time.utc(2024, 3, 4, 12, 0, 0, 0)
    mixin_bag_repo.create(identifier: bag_identifier_one, group_part: 1, repository_package_identifier: mixin_package_identifier)
    mixin_bag_repo.create(identifier: bag_identifier_two, group_part: 1, repository_package_identifier: second_package_identifier)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_identifier_one, timestamp: start_time)
    mixin_repo.create(status: BagStatus::COPIED, bag_identifier: bag_identifier_one, timestamp: start_time + 30)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_identifier_one, timestamp: start_time + 60)
    mixin_repo.create(status: BagStatus::COPIED, bag_identifier: bag_identifier_one, timestamp: start_time + 90)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_identifier_two, timestamp: start_time + 100)
    mixin_repo.create(status: BagStatus::COPIED, bag_identifier: bag_identifier_two, timestamp: start_time + 120)
    event = mixin_repo.get_latest_event_for_bag(bag_identifier: bag_identifier_one)
    assert event.is_a?(StatusEventRepository::StatusEvent)
    assert_equal bag_identifier_one, event.bag_identifier
    assert_equal BagStatus::COPIED, event.status
    assert_equal start_time + 90, event.timestamp
  end

  def test_get_latest_event_for_bag_when_nil
    event = mixin_repo.get_latest_event_for_bag(bag_identifier: mixin_bag_identifier)
    refute event
  end

  def start_time
    Time.utc(2024, 3, 4, 12, 0, 0, 0)
  end

  def create_latest_event_for_bags_test_data
    bag_id_one, bag_id_two, bag_id_three, bag_id_four = 1.upto(4).map do |num|
      package_identifier = "00000#{num}"
      mixin_package_repo.create(
        identifier: package_identifier, repository_name: "repository", updated_at: Time.now.utc
      )
      bag_identifier = "repository.context-#{package_identifier}"
      mixin_bag_repo.create(
        identifier: bag_identifier, group_part: 1, repository_package_identifier: package_identifier
      )
      bag_identifier
    end

    start = start_time

    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_id_one, timestamp: start - 60)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_id_two, timestamp: start - 60)
    mixin_repo.create(status: BagStatus::COPIED, bag_identifier: bag_id_two, timestamp: start - 30)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_id_two, timestamp: start)
    mixin_repo.create(status: BagStatus::COPIED, bag_identifier: bag_id_two, timestamp: start + 30)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_id_two, timestamp: start + 60)
    mixin_repo.create(status: BagStatus::DEPOSITED, bag_identifier: bag_id_two, timestamp: start + 90)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_id_three, timestamp: start + 100)
    mixin_repo.create(status: BagStatus::COPIED, bag_identifier: bag_id_three, timestamp: start + 120)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_id_four, timestamp: start + 140)
    mixin_repo.create(status: BagStatus::FAILED, bag_identifier: bag_id_four, timestamp: start + 160)
    mixin_repo.create(status: BagStatus::COPYING, bag_identifier: bag_id_three, timestamp: start + 180)
    mixin_repo.create(status: BagStatus::FAILED, bag_identifier: bag_id_three, timestamp: start + 200)

    [bag_id_one, bag_id_two, bag_id_three, bag_id_four]
  end

  def test_get_latest_event_for_bags_when_no_events
    start = Time.utc(2024, 5, 4, 12, 0, 0, 0)
    bag_events = mixin_repo.get_latest_event_for_bags(start_time: start)
    assert_equal 0, bag_events.length
  end

  def test_get_latest_event_for_bags
    bag_id_two, bag_id_three, bag_id_four = create_latest_event_for_bags_test_data[1, 3]
    bag_events = mixin_repo.get_latest_event_for_bags(start_time: start_time)

    bag_events.each do |bag_event|
      assert bag_event.is_a?(StatusEventRepository::StatusEvent)
    end

    events_before_start = bag_events.filter { |e| e.timestamp < start_time }
    assert_equal 0, events_before_start.length

    assert_equal 3, bag_events.length
    id_status_pairs = bag_events.sort_by { |e| e.timestamp }.map { |e| [e.bag_identifier, e.status] }
    assert_equal(
      [
        [bag_id_two, BagStatus::DEPOSITED],
        [bag_id_four, BagStatus::FAILED],
        [bag_id_three, BagStatus::FAILED]
      ],
      id_status_pairs
    )
  end

  def test_get_latest_event_for_bags_with_no_start_time
    bag_id_one, bag_id_two, bag_id_three, bag_id_four = create_latest_event_for_bags_test_data
    bag_events = mixin_repo.get_latest_event_for_bags

    assert_equal 4, bag_events.length
    id_status_pairs = bag_events.sort_by { |e| e.timestamp }.map { |e| [e.bag_identifier, e.status] }
    assert_equal(
      [
        [bag_id_one, BagStatus::COPYING],
        [bag_id_two, BagStatus::DEPOSITED],
        [bag_id_four, BagStatus::FAILED],
        [bag_id_three, BagStatus::FAILED]
      ],
      id_status_pairs
    )
  end
end

class StatusEventInMemoryRepositoryTest < Minitest::Test
  include StatusEventRepositorySharedTest
  include SemanticLogger::Loggable

  def setup
    @repo = StatusEventRepository::StatusEventInMemoryRepository.new

    @bag_repo = BagRepository::BagInMemoryRepository.new
    @bag_identifier = "repository.context-000001"

    @package_repo = RepositoryPackageRepository::RepositoryPackageInMemoryRepository.new
    @package_identifier = "000001"
  end

  def mixin_repo
    @repo
  end

  def mixin_bag_repo
    @bag_repo
  end

  def mixin_bag_identifier
    @bag_identifier
  end

  def mixin_package_repo
    @package_repo
  end

  def mixin_package_identifier
    @package_identifier
  end

  def test_create
    timestamp = Time.now.utc
    @repo.create(
      status: BagStatus::BAGGED,
      bag_identifier: @bag_identifier,
      timestamp: timestamp,
      note: "something happening here"
    )
    expected = [
      StatusEventRepository::StatusEvent.new(
        id: 0,
        status: BagStatus::BAGGED,
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
    @bag_identifier = "repository.context-000001"

    @package_repo = RepositoryPackageRepository::RepositoryPackageDatabaseRepository.new
    @package_identifier = "000001"
  end

  def mixin_repo
    @repo
  end

  def mixin_bag_repo
    @bag_repo
  end

  def mixin_bag_identifier
    @bag_identifier
  end

  def mixin_package_repo
    @package_repo
  end

  def mixin_package_identifier
    @package_identifier
  end

  def test_create
    @package_repo.create(identifier: @package_identifier, repository_name: "repository-1", updated_at: Time.now.utc)
    @bag_repo.create(identifier: @bag_identifier, group_part: 2, repository_package_identifier: @package_identifier)
    timestamp = Time.now.utc.floor(6)  # To match database precision
    @repo.create(
      status: BagStatus::BAGGED,
      bag_identifier: @bag_identifier,
      timestamp: timestamp,
      note: nil
    )
    status_events = DatabaseSchema::StatusEvent.eager(:status, :bag).all
    assert_equal 1, status_events.length
    status_event = status_events[0]
    assert_equal BagStatus::BAGGED, status_event.status.name
    assert_equal @bag_identifier, status_event.bag.identifier
    assert_equal timestamp, status_event.timestamp
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
