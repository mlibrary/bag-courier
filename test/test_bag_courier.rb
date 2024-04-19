require "minitar"
require "minitest/autorun"
require "minitest/pride"
require "semantic_logger"

require_relative "setup_db"
require_relative "../lib/bag_adapter"
require_relative "../lib/bag_courier"
require_relative "../lib/bag_repository"
require_relative "../lib/bag_status"
require_relative "../lib/bag_tag"
require_relative "../lib/bag_validator"
require_relative "../lib/config"
require_relative "../lib/data_transfer"
require_relative "../lib/remote_client"
require_relative "../lib/repository_package_repository"
require_relative "../lib/status_event_repository"

SemanticLogger.add_appender(io: $stderr, formatter: :color)
SemanticLogger.default_level = :debug

class BagIdTest < Minitest::Test
  def test_to_s
    expected = "somerepo.uniqueid"
    assert_equal expected, BagCourier::BagId.new(
      repository: "somerepo", object_id: "uniqueid"
    ).to_s
  end

  def test_to_s_with_context
    expected = "somerepo.somecontext-uniqueid"
    assert_equal expected, BagCourier::BagId.new(
      repository: "somerepo", object_id: "uniqueid", context: "somecontext"
    ).to_s
  end

  def test_to_s_with_part
    expected = "somerepo.uniqueid-4"
    assert_equal expected, BagCourier::BagId.new(
      repository: "somerepo", object_id: "uniqueid", part_id: "4"
    ).to_s
  end

  def test_to_s_with_context_and_part
    expected = "somerepo.somecontext-uniqueid-4"
    assert_equal expected, BagCourier::BagId.new(
      repository: "somerepo",
      object_id: "uniqueid",
      context: "somecontext",
      part_id: "4"
    ).to_s
  end
end

class BagCourierTest < SequelTestCase
  def setup
    # Set up test directories and files
    @test_dir_path = File.join(__dir__, "bag_courier_test")
    @prep_path = File.join(@test_dir_path, "prep")
    @export_path = File.join(@test_dir_path, "export")
    @package_path = File.join(@test_dir_path, "package")
    FileUtils.rm_r(@test_dir_path) if File.exist?(@test_dir_path)
    FileUtils.mkdir_p([@test_dir_path, @prep_path, @export_path, @package_path])
    innerbag = BagAdapter::BagAdapter.new(@package_path)

    File.write(
      File.join(@package_path, "data", "something.txt"),
      "Something to be preserved"
    )
    innerbag.add_bag_info({})
    innerbag.add_manifests
    @validator = InnerBagValidator.new("package")
    # Set up remote-related objects
    @data_transfer = DataTransfer::RemoteClientDataTransfer.new(
      remote_client: RemoteClient::FileSystemRemoteClient.new(
        File.join(@package_path)
      )
    )

    @mock_target_client = Minitest::Mock.new
    @aptrust_target_client = RemoteClient::RemoteClientFactory.from_config(
      type: :aptrust,
      settings: Config::AptrustAwsRemoteConfig.new(
        region: "us-east-2",
        receiving_bucket: "aptrust.receiving.someorg.edu",
        restore_bucket: "aptrust.restore.someorg.edu",
        access_key_id: "some-access-key",
        secret_access_key: "some-secret-key"
      )
    )

    # Set up data
    @object_id = "000001"
    @repository_name = "fake-repository"
    @bag_id = BagCourier::BagId.new(
      repository: @repository_name,
      object_id: @object_id,
      context: "context"
    )
    @bag_info = BagTag::BagInfoBagTag.new(
      identifier: @bag_id.to_s,
      description: "This is a bagged object from a fake repository!"
    )
    @aptrust_info = BagTag::AptrustInfoBagTag.new(
      title: "Test object",
      description: "This is a bagged object from a fake repository!",
      item_description: "This is an exquisite example of a test object.",
      creator: "Test Test"
    )

    # Set up repositories and add records
    @package_repo = RepositoryPackageRepository::RepositoryPackageDatabaseRepository.new
    @bag_repo = BagRepository::BagDatabaseRepository.new
    @status_event_repo = StatusEventRepository::StatusEventDatabaseRepository.new
    @package_repo.create(
      identifier: @object_id,
      repository_name: @repository_name,
      updated_at: Time.now.utc
    )
    @bag_repo.create(
      identifier: @bag_id.to_s,
      group_part: 1,
      repository_package_identifier: @object_id
    )
  end

  def create_courier(dry_run:, target_client:, validator: @validator, remove_export: false)
    BagCourier::BagCourier.new(
      bag_id: @bag_id,
      bag_info: @bag_info,
      tags: [@aptrust_info],
      data_transfer: @data_transfer,
      working_dir: @prep_path,
      export_dir: @export_path,
      remove_export: remove_export,
      dry_run: dry_run,
      status_event_repo: @status_event_repo,
      target_client: target_client,
      validator: validator
    )
  end

  def test_deliver_with_dry_run_false
    courier = create_courier(dry_run: false, target_client: @mock_target_client)
    expected_tar_file_path = File.join(@export_path, @bag_id.to_s + ".tar")
    @mock_target_client.expect(:remote_text, "AWS S3 remote location in bucket fake")
    @mock_target_client.expect(:send_file, nil, local_file_path: expected_tar_file_path)
    courier.deliver
    @mock_target_client.verify

    expected_statuses = [
      BagStatus::BAGGING, BagStatus::COPYING, BagStatus::COPIED, BagStatus::VALIDATING, BagStatus::VALIDATED, BagStatus::BAGGED, BagStatus::PACKING,
      BagStatus::PACKED, BagStatus::DEPOSITING, BagStatus::DEPOSITED
    ]
    statuses = @status_event_repo.get_all.sort_by(&:timestamp).map(&:status)
    assert_equal expected_statuses, statuses

    assert File.exist?(expected_tar_file_path)
    Minitar.unpack(expected_tar_file_path, @export_path)
    untarred_bag_path = File.join(@export_path, @bag_id.to_s)
    assert Dir.exist?(untarred_bag_path)
    assert File.exist?(File.join(untarred_bag_path, "data", "package", "data", "something.txt"))
    assert File.exist?(File.join(untarred_bag_path, "aptrust-info.txt"))
  end

  def test_deliver_with_dry_run
    courier = create_courier(dry_run: true, target_client: @mock_target_client)
    courier.deliver
    @mock_target_client.verify

    expected_statuses = [
      BagStatus::BAGGING, BagStatus::COPYING, BagStatus::COPIED, BagStatus::VALIDATING, BagStatus::VALIDATED, BagStatus::BAGGED, BagStatus::PACKING,
      BagStatus::PACKED, BagStatus::DEPOSIT_SKIPPED
    ]
    statuses = @status_event_repo.get_all.sort_by(&:timestamp).map(&:status)
    assert_equal expected_statuses, statuses

    expected_tar_file_path = File.join(@export_path, @bag_id.to_s + ".tar")
    assert File.exist?(expected_tar_file_path)
  end

  def test_deliver_when_deposit_raises_error
    courier = create_courier(dry_run: false, target_client: @aptrust_target_client)
    raise_error = proc { raise RemoteClient::RemoteClientError, "specific details" }
    @aptrust_target_client.stub :send_file, raise_error do
      courier.deliver
    end
    expected_statuses = [
      BagStatus::BAGGING, BagStatus::COPYING, BagStatus::COPIED, BagStatus::VALIDATING, BagStatus::VALIDATED, BagStatus::BAGGED, BagStatus::PACKING,
      BagStatus::PACKED, BagStatus::DEPOSITING, BagStatus::FAILED
    ]
    statuses = @status_event_repo.get_all.sort_by(&:timestamp).map(&:status)
    assert_equal expected_statuses, statuses
  end

  def test_deliver_with_remove_export
    courier = create_courier(dry_run: false, target_client: @mock_target_client, remove_export: true)
    expected_tar_file_path = File.join(@export_path, @bag_id.to_s + ".tar")
    @mock_target_client.expect(:remote_text, "AWS S3 remote location in bucket fake")
    @mock_target_client.expect(:send_file, nil, local_file_path: expected_tar_file_path)
    courier.deliver
    @mock_target_client.verify

    refute File.exist?(expected_tar_file_path)
  end
end
