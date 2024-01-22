require "securerandom"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/archivematica"

class ArchivematicaAPITest < Minitest::Test
  def setup
    base_url = "http://archivematica.storage.api.org:8000"
    username = "youruser"
    api_key = "some-secret-key"
    api_prefix = "/api/v2/"

    @location_uuid = SecureRandom.uuid
    @location_url = "#{api_prefix}location/#{@location_uuid}/"
    @request_url_stem = base_url + api_prefix

    @stubs = Faraday::Adapter::Test::Stubs.new
    stubbed_test_conn = Faraday.new(
      url: "#{base_url}#{api_prefix}",
      headers: {"Authorization" => "ApiKey #{username}:#{api_key}"}
    ) do |builder|
      # TO DO: These settings make the tests succeed, so how do I make them part of the class/constructor?
      builder.request :retry
      builder.response :raise_error

      builder.adapter :test, @stubs
    end
    @stubbed_api = Archivematica::ArchivematicaAPI.new(
      stubbed_test_conn,
      api_prefix: api_prefix
    )

    @api = Archivematica::ArchivematicaAPI.from_config(
      base_url: base_url,
      username: username,
      api_key: api_key
    )
  end

  def make_path(uuid)
    uuid.delete("-").chars.each_slice(4).map(&:join).join("/")
  end

  def test_get_throws_appropriate_error
    @stubs.get(@request_url_stem + "file/") do |env|
      [401, {"Content-Type": "text/plain"}, "Unauthorized"]
    end
    error = assert_raises Archivematica::ArchivematicaAPIError do
      @stubbed_api.get("file/")
    end
    message = "Error occurred while interacting with Archivematica API. " \
      "Error type: Faraday::UnauthorizedError; " \
      "status code: 401; " \
      "body: Unauthorized"
    assert_equal message, error.message
  end

  def test_get_retries_on_timeout_to_failure
    calls = 0
    @stubs.get(@request_url_stem + "file/") do |env|
      calls += 1
      env[:body] = nil
      raise Faraday::TimeoutError
    end

    # Final error is caught and transformed.
    error = assert_raises Archivematica::ArchivematicaAPIError do
      @stubbed_api.get("file/")
    end
    assert error.message.include?("Faraday::TimeoutError")

    assert_equal 3, calls
  end

  def test_get_retries_on_timeout_failing_once_then_succeeding
    calls = 0
    @stubs.get(@request_url_stem + "file/") do |env|
      env[:body] = nil
      calls += 1
      if calls < 2
        raise Faraday::TimeoutError
      else
        [200, {"Content-Type": "application/json"}, "{}"]
      end
    end

    data = @stubbed_api.get("file/")
    assert_equal 2, calls
    assert_equal ({}), data
  end

  def test_get_packages
    uuids = Array.new(4) { SecureRandom.uuid }
    data = [
      {
        "uuid" => uuids[0],
        "current_full_path" => "/storage/#{make_path(uuids[0])}/identifier-one-#{uuids[0]}",
        "size" => 1000,
        "stored_date" => "2024-01-17T00:00:00.000000",
        "status" => "UPLOADED",
        "current_location" => @location_url
      },
      {
        "uuid" => uuids[1],
        "current_full_path" => "/storage/#{make_path(uuids[1])}/identifier-two-#{uuids[1]}",
        "size" => 300000,
        "stored_date" => "2024-01-16T00:00:00.000000",
        "status" => "DELETED",
        "current_location" => @location_url
      },
      {
        "uuid" => uuids[2],
        "current_full_path" => "/storage/#{make_path(uuids[2])}/identifier-two-#{uuids[2]}",
        "size" => 5000000,
        "stored_date" => "2024-01-13T00:00:00.000000",
        "status" => "UPLOADED",
        "current_location" => @location_url
      }
    ]

    @api.stub :get_objects_from_pages, data do
      packages = @api.get_packages(location_uuid: @location_uuid)
      assert_equal 2, packages.length
      if packages.length == 2
        assert_equal [uuids[0], uuids[2]], packages.map { |p| p.uuid }
      end
    end
  end

  def teardown
    Faraday.default_connection = nil
  end
end
