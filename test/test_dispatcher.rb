require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../lib/bag_courier"
require_relative "../lib/bag_repository"
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
      name: "Some Repository",
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
      target_client: target_client,
      bag_repo: BagRepository::BagDatabaseRepository.new,
      status_event_repo: StatusEventRepository::StatusEventDatabaseRepository.new
    )
  end

  def test_dispatcher_setup
    assert @dispatcher.respond_to?(:dispatch)
    assert @dispatcher.bag_repo.is_a?(BagRepository::BagDatabaseRepository)
    assert @dispatcher.status_event_repo.is_a?(
      StatusEventRepository::StatusEventDatabaseRepository
    )
  end

  def test_dispatch
    courier = @dispatcher.dispatch(
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
      context: "some-context",
      validator: InnerBagValidator.new("some-inner-bag-name"),
      extra_bag_info_data: {something_extra: true}
    )
    assert courier.is_a?(BagCourier::BagCourier)
  end
end
