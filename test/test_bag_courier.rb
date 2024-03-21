require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../lib/bag_courier"
require_relative "../lib/bag_repository"
require_relative "../lib/bag_tag"
require_relative "../lib/data_transfer"
require_relative "../lib/remote_client"
require_relative "../lib/repository_package_repository"
require_relative "../lib/status_event_repository"

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
    @remote_path = File.join(@test_dir_path, "remote")
    FileUtils.rm_r(@test_dir_path)
    FileUtils.mkdir_p([@test_dir_path, @prep_path, @export_path, @remote_path])
    File.write(
      File.join(@remote_path, "something.txt"),
      "Something to be preserved"
    )

    # Set up remote-related objects
    @data_transfer = DataTransfer::RemoteClientDataTransfer.new(
      remote_client: RemoteClient::FileSystemRemoteClient.new(
        File.join(@remote_path)
      )
    )
    @mock_target_client = Minitest::Mock.new

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

  def create_courier(dry_run)
    BagCourier::BagCourier.new(
      bag_id: @bag_id,
      bag_info: @bag_info,
      tags: [@aptrust_info],
      data_transfer: @data_transfer,
      working_dir: @prep_path,
      export_dir: @export_path,
      dry_run: dry_run,
      status_event_repo: @status_event_repo,
      target_client: @mock_target_client
    )
  end

  def test_deliver_with_dry_run_false
    courier = create_courier(false)

    expected_tar_file_name = File.join(@export_path, @bag_id.to_s + ".tar")
    @mock_target_client.expect(:remote_text, "AWS S3 remote location in bucket fake")
    @mock_target_client.expect(:send_file, nil, local_file_path: expected_tar_file_name)
    courier.deliver
    @mock_target_client.verify

    expected_statuses = [
      "bagging", "copying", "copied", "bagged", "packing",
      "packed", "depositing", "deposited"
    ]
    statuses = @status_event_repo.get_all.sort_by(&:timestamp).map(&:status)
    assert_equal expected_statuses, statuses
  end

  def test_deliver_with_dry_run
    courier = create_courier(true)

    courier.deliver
    @mock_target_client.verify

    expected_statuses = [
      "bagging", "copying", "copied", "bagged", "packing",
      "packed", "deposit_skipped"
    ]
    statuses = @status_event_repo.get_all.sort_by(&:timestamp).map(&:status)
    assert_equal expected_statuses, statuses
  end
end
