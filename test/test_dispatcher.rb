require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../lib/bag_courier"
require_relative "../lib/bag_repository"
require_relative "../lib/bag_tag"
require_relative "../lib/bag_validator"
require_relative "../lib/config"
require_relative "../lib/data_transfer"
require_relative "../lib/dispatcher"
require_relative "../lib/remote_client"
require_relative "../lib/repository_data"
require_relative "../lib/repository_package_repository"
require_relative "../lib/status_event_repository"

class APTrustDispatcherTest < SequelTestCase
  def setup
    settings = Config::SettingsConfig.new(
      working_dir: "/prep",
      export_dir: "/export",
      remove_export: true,
      dry_run: false,

      # not used by Dispatchers
      log_level: :debug,
      object_size_limit: nil
    )
    repository = Config::RepositoryConfig.new(
      name: "some-repo",
      description: "Bag containing an item from some repository"
    )
    target_client = RemoteClient::RemoteClientFactory.from_config(
      type: :aptrust,
      settings: Config::AptrustAwsRemoteConfig.new(
        region: "us-east-1",
        receiving_bucket: "aptrust.receiving.org.edu",
        restore_bucket: "aptrust.restore.org.edu",
        access_key_id: "some-key-id",
        secret_access_key: "some-secret-key"
      )
    )

    @package_identifier = "00001"
    RepositoryPackageRepository::RepositoryPackageDatabaseRepository.new.create(
      identifier: @package_identifier,
      repository_name: repository.name,
      updated_at: Time.now.utc
    )

    @dispatcher = Dispatcher::APTrustDispatcher.new(
      settings: settings,
      repository: repository,
      context: "some-context",
      extra_bag_info_data: {"something_extra" => true},
      target_client: target_client,
      bag_repo: BagRepository::BagDatabaseRepository.new,
      status_event_repo: StatusEventRepository::StatusEventDatabaseRepository.new
    )

    @bag_identifier = "some-repo.some-context-00001"
  end

  def create_courier_with_dispatch
    @dispatcher.dispatch(
      object_metadata: RepositoryData::ObjectMetadata.new(
        id: @package_identifier,
        title: "Some title",
        creator: "Some creator",
        description: "Something something something"
      ),
      data_transfer: DataTransfer::RemoteClientDataTransfer.new(
        remote_client: RemoteClient::FileSystemRemoteClient.new("/some/path"),
        remote_path: "some_subdir"
      ),
      validator: InnerBagValidator.new("some-inner-bag-name")
    )
  end

  def test_dispatcher_setup
    assert @dispatcher.respond_to?(:dispatch)
    assert @dispatcher.bag_repo.is_a?(BagRepository::BagDatabaseRepository)
    assert @dispatcher.status_event_repo.is_a?(
      StatusEventRepository::StatusEventDatabaseRepository
    )
  end

  def test_dispatch_creates_courier
    courier = create_courier_with_dispatch
    assert courier.is_a?(BagCourier::BagCourier)
  end

  def test_dispatched_courier_has_correct_id
    courier = create_courier_with_dispatch
    assert courier.bag_id.is_a?(BagCourier::BagId)
    assert_equal @bag_identifier, courier.bag_id.to_s
  end

  def test_dispatched_courier_has_extra_bag_info
    courier = create_courier_with_dispatch
    assert_equal true, courier.bag_info.data["something_extra"]
  end

  def test_dispatched_courier_has_correct_tags
    courier = create_courier_with_dispatch
    assert_equal 1, courier.tags.length
    assert courier.tags[0].is_a?(BagTag::AptrustInfoBagTag)
  end

  def test_dispatcher_creates_bag_record
    create_courier_with_dispatch
    bag = BagRepository::BagDatabaseRepository.new.get_by_identifier(@bag_identifier)
    assert !bag.nil?
    assert_equal bag.group_part, 1
  end
end
