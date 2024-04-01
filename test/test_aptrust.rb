require "minitest/autorun"
require "minitest/pride"

require_relative "setup_db"
require_relative "../lib/aptrust"
require_relative "../lib/api_backend"
require_relative "../lib/bag_status"
require_relative "../lib/status_event_repository"

class APTrustAPITest < Minitest::Test
  include APTrust

  def setup
    @base_url = "https://fake.aptrust.org"
    @username = "youruser"
    @api_key = "some-secret-key"
    @api_prefix = "/member-api/v3/"
    @object_id_prefix = "umich.edu/"
    @bag_identifier = "repository.context-001"
    @deposited_at = Time.utc(2024, 3, 18, 0, 1)

    @expected_params = {
      object_identifier: @object_id_prefix + @bag_identifier,
      action: "Ingest",
      date_processed__gteq: "2024-03-18T00:00:00.000000",
      per_page: 1,
      sort: "date_processed__desc"
    }

    @mock_backend = Minitest::Mock.new
    @mocked_api = APTrustAPI.new(
      api_backend: @mock_backend,
      api_prefix: @api_prefix,
      object_id_prefix: @object_id_prefix
    )
  end

  def test_from_config_creates_instance
    api = APTrustAPI.from_config(
      base_url: @base_url,
      username: @username,
      api_key: @api_key,
      api_backend: APIBackend::FaradayAPIBackend,
      api_prefix: @api_prefix,
      object_id_prefix: @object_id_prefix
    )
    assert api.is_a?(APTrustAPI)
  end

  def test_get_ingest_status_not_found
    data = {"results" => nil}
    @mock_backend.expect(:get, data, ["items", @expected_params])
    assert_equal "not found", @mocked_api.get_ingest_status(
      bag_identifier: @bag_identifier, deposited_at: @deposited_at
    )
    @mock_backend.verify
  end

  def test_get_ingest_status_failed
    data = {"results" => [{"status" => "faiLed"}]}
    @mock_backend.expect(:get, data, url: "items", params: @expected_params)
    assert_equal "failed", @mocked_api.get_ingest_status(
      bag_identifier: @bag_identifier, deposited_at: @deposited_at
    )
    @mock_backend.verify
  end

  def test_get_ingest_status_cancelled
    data = {"results" => [{"status" => "Cancelled"}]}
    @mock_backend.expect(:get, data, url: "items", params: @expected_params)
    assert_equal "cancelled", @mocked_api.get_ingest_status(
      bag_identifier: @bag_identifier, deposited_at: @deposited_at
    )
    @mock_backend.verify
  end

  def test_get_ingest_status_success
    data = {"results" => [{"status" => "Success", "stage" => "Cleanup"}]}
    @mock_backend.expect(:get, data, url: "items", params: @expected_params)
    assert_equal "success", @mocked_api.get_ingest_status(
      bag_identifier: @bag_identifier, deposited_at: @deposited_at
    )
    @mock_backend.verify
  end

  def test_get_ingest_status_processing
    data = {"results" => [{"status" => "something_unexpected"}]}
    @mock_backend.expect(:get, data, url: "items", params: @expected_params)
    assert_equal "processing", @mocked_api.get_ingest_status(
      bag_identifier: @bag_identifier, deposited_at: @deposited_at
    )
    @mock_backend.verify
  end
end

class APTrustVerifierTest < SequelTestCase
  include APTrust

  def setup
    @bag_identifier = "repository.context-0001"
    @mock_api = Minitest::Mock.new
    @status_event_repo = StatusEventRepository::StatusEventInMemoryRepository.new
    @deposited_at = Time.utc(2024, 3, 18)

    @verifier = APTrustVerifier.new(
      aptrust_api: @mock_api, status_event_repo: @status_event_repo
    )

    @status_event_repo.create(
      bag_identifier: @bag_identifier,
      status: BagStatus::DEPOSITED,
      timestamp: @deposited_at
    )
  end

  def test_verify_with_success
    @mock_api.expect(
      :get_ingest_status,
      IngestStatus::SUCCESS,
      bag_identifier: @bag_identifier,
      deposited_at: @deposited_at
    )
    @verifier.verify(bag_identifier: @bag_identifier, deposited_at: @deposited_at)
    @mock_api.verify

    event = @status_event_repo.get_latest_event_for_bag(bag_identifier: @bag_identifier)
    assert event
    assert BagStatus::VERIFIED, event.status
  end

  def test_verify_with_failure
    @mock_api.expect(
      :get_ingest_status,
      IngestStatus::FAILED,
      bag_identifier: @bag_identifier,
      deposited_at: @deposited_at
    )
    @verifier.verify(bag_identifier: @bag_identifier, deposited_at: @deposited_at)
    @mock_api.verify

    event = @status_event_repo.get_latest_event_for_bag(bag_identifier: @bag_identifier)
    assert event
    assert BagStatus::VERIFY_FAILED, event.status
  end

  def test_verify_with_processing
    @mock_api.expect(
      :get_ingest_status,
      IngestStatus::PROCESSING,
      bag_identifier: @bag_identifier,
      deposited_at: @deposited_at
    )
    @verifier.verify(bag_identifier: @bag_identifier, deposited_at: @deposited_at)
    @mock_api.verify

    event = @status_event_repo.get_latest_event_for_bag(bag_identifier: @bag_identifier)
    assert_equal BagStatus::DEPOSITED, event.status  # No verify event
  end

  def test_verify_with_not_found
    @mock_api.expect(
      :get_ingest_status,
      IngestStatus::PROCESSING,
      bag_identifier: @bag_identifier,
      deposited_at: @deposited_at
    )
    @verifier.verify(bag_identifier: @bag_identifier, deposited_at: @deposited_at)
    @mock_api.verify

    event = @status_event_repo.get_latest_event_for_bag(bag_identifier: @bag_identifier)
    assert_equal BagStatus::DEPOSITED, event.status  # No verify event
  end
end
