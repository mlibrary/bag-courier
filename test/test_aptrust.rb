require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/aptrust"

class APTrustAPITest < Minitest::Test
  include APTrust

  def setup
    base_url = "https://fake.aptrust.org"
    username = "youruser"
    api_key = "some-secret-key"
    api_prefix = "/member-api/v3/"
    @request_url_stem = base_url + api_prefix
    @bag_identifier = "repository.context-001"

    @stubs = Faraday::Adapter::Test::Stubs.new
    stubbed_test_conn = Faraday.new(
      url: "#{base_url}#{api_prefix}",
      headers: {
        :accept => "application/json",
        :content_type => "application/json",
        "X-Pharos-API-User" => username,
        "X-Pharos-API-Key" => api_key
      }
    ) do |builder|
      builder.request :retry
      builder.response :raise_error

      builder.adapter :test, @stubs
    end

    @stubbed_api = APTrustAPI.new(stubbed_test_conn)
    @api = APTrustAPI.from_config(
      base_url: base_url,
      username: username,
      api_key: api_key
    )
  end

  def test_get_throws_unauthorized_error_with_response_info
    @stubs.get(@request_url_stem + "items/") do |env|
      [401, {"Content-Type": "text/plain"}, "Unauthorized"]
    end
    error = assert_raises APTrustAPIError do
      @stubbed_api.get("items/")
    end
    expected = "Error occurred while interacting with APTrust API. " \
      "Error type: Faraday::UnauthorizedError; " \
      "status code: 401; " \
      "body: Unauthorized"
    assert_equal expected, error.message
  end

  def test_get_retries_on_timeout_to_failure
    calls = 0
    @stubs.get(@request_url_stem + "items/") do |env|
      calls += 1
      env[:body] = nil
      raise Faraday::TimeoutError
    end

    # Final error is caught and transformed.
    error = assert_raises APTrustAPIError do
      @stubbed_api.get("items/")
    end
    expected = "Error occurred while interacting with APTrust API. " \
      "Error type: Faraday::TimeoutError; " \
      "status code: none; " \
      "body: none"
    assert_equal expected, error.message

    assert_equal 3, calls
  end

  def test_get_retries_on_timeout_failing_once_then_succeeding
    calls = 0
    @stubs.get(@request_url_stem + "items/") do |env|
      env[:body] = nil
      calls += 1
      if calls < 2
        raise Faraday::TimeoutError
      else
        [200, {"Content-Type": "application/json"}, "{}"]
      end
    end

    data = @stubbed_api.get("items/")
    assert_equal 2, calls
    assert_equal ({}), data
  end

  def test_get_ingest_status_not_found
    data = {"results" => []}
    @api.stub :get, data do
      assert_equal "not found", @api.get_ingest_status(@bag_identifier)
    end
  end

  def test_get_ingest_status_failed
    data = {"results" => [{"status" => "faiLed"}]}
    @api.stub :get, data do
      assert_equal "failed", @api.get_ingest_status(@bag_identifier)
    end
  end

  def test_get_ingest_status_cancelled
    data = {"results" => [{"status" => "Cancelled"}]}
    @api.stub :get, data do
      assert_equal "cancelled", @api.get_ingest_status(@bag_identifier)
    end
  end

  def test_get_ingest_status_success
    data = {"results" => [{"status" => "Success", "stage" => "Cleanup"}]}
    @api.stub :get, data do
      assert_equal "success", @api.get_ingest_status(@bag_identifier)
    end
  end

  def test_get_ingest_status_processing
    data = {"results" => [{"status" => "something_unexpected"}]}
    @api.stub :get, data do
      assert_equal "processing", @api.get_ingest_status(@bag_identifier)
    end
  end

  def teardown
    Faraday.default_connection = nil
  end
end
