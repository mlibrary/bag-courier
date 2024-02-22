require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../lib/status_event"
require_relative "../lib/bag_repository"

module StatusEventRepositorySharedTest
  def test_create_with_unknown_status
    assert_raises(StatusEvent::UnknownStatusError) do
      mixin_repo.create(
        bag_id: mixin_bag_id,
        status: "turned_inside_out",
        timestamp: Time.now.utc
      )
    end
  end

  def test_get_all
    mixin_bag_repo.create(identifier: mixin_bag_id, group_part: 1)

    ["bagging", "copying", "copied", "bagged"].each do |s|
      mixin_repo.create(
        status: s,
        bag_id: mixin_bag_id,
        timestamp: Time.now.utc
      )
    end
    status_events = mixin_repo.get_all
    assert_equal 4, status_events.size
    assert status_events.all? { |s| s.is_a?(StatusEvent::StatusEvent) }
  end

  def test_get_all_for_bag_id
    bag_id_one = mixin_bag_id
    bag_id_two = "repository.context-002"

    mixin_bag_repo.create(identifier: bag_id_one, group_part: 1)
    mixin_bag_repo.create(identifier: bag_id_two, group_part: 1)

    mixin_repo.create(status: "bagging", bag_id: bag_id_one, timestamp: Time.now.utc)
    mixin_repo.create(status: "bagging", bag_id: bag_id_two, timestamp: Time.now.utc)
    mixin_repo.create(status: "bagged", bag_id: bag_id_two, timestamp: Time.now.utc)

    mixin_repo.get_all_for_bag_id(bag_id_two)
  end

end

class StatusEventInMemoryRepositoryTest < Minitest::Test
  include StatusEventRepositorySharedTest

  def setup
    @bag_id = "repository.context-001"
    @repo = StatusEvent::StatusEventInMemoryRepository.new
    @bag_repo = BagRepository::BagInMemoryRepository.new
  end

  def mixin_bag_id
    @bag_id
  end

  def mixin_repo
    @repo
  end

  def mixin_bag_repo
    @bag_repo
  end

  def test_create
    timestamp = Time.now.utc
    event_data = {
      status: "bagged",
      bag_id: @bag_id,
      timestamp: timestamp,
      note: "something happening here"
    }
    @repo.create(event_data)

    expected = [
      StatusEvent::StatusEvent.new(
        id: 0,
        status: "bagged",
        bag_id: @bag_id,
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
    @bag_id = "repository.context-001"
    @repo = StatusEvent::StatusEventDatabaseRepository.new(DB)
    @bag_repo = BagRepository::BagDatabaseRepository.new(DB)
  end

  def mixin_bag_id
    @bag_id
  end

  def mixin_repo
    @repo
  end

  def mixin_bag_repo
    @bag_repo
  end

  def test_create
    @bag_repo.create(identifier: @bag_id, group_part: 2)
    bag_db_id = @bag_repo.get_by_identifier(@bag_id).id

    timestamp = Time.now.utc.floor(6)
    event_data = {
      status: "bagged",
      bag_id: @bag_id,
      timestamp: timestamp
    }
    @repo.create(event_data)

    status_events = DB.from(:status_event).join(:status, id: :status_id).all
    assert_equal 1, status_events.length
    status_event = status_events[0]
    assert_equal "bagged", status_event[:name]
    assert_equal bag_db_id, status_event[:bag_id]
    assert_equal timestamp, status_event[:timestamp]
  end
end
