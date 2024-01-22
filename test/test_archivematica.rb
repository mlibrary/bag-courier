require "logger"
require "securerandom"

require "minitest/autorun"
require "minitest/pride"

require_relative "../lib/archivematica"

class ArchivematicaAPITest < Minitest::Test
  def setup
    @location_uuid = SecureRandom.uuid
    @location_url = "/api/v2/location/#{@location_uuid}/"
    @api = Archivematica::ArchivematicaAPI.new(
      base_url: "http://archivematica.storage.api.org:8000",
      username: "youruser",
      api_key: "some-secret-key"
    )
  end

  def make_path(uuid)
    uuid.delete("-").chars.each_slice(4).map(&:join).join("/")
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
        "current_location" => @location_uuid
      },
      {
        "uuid" => uuids[1],
        "current_full_path" => "/storage/#{make_path(uuids[1])}/identifier-two-#{uuids[1]}",
        "size" => 300000,
        "stored_date" => "2024-01-16T00:00:00.000000",
        "status" => "DELETED",
        "current_location" => @location_uuid
      },
      {
        "uuid" => uuids[2],
        "current_full_path" => "/storage/#{make_path(uuids[2])}/identifier-two-#{uuids[2]}",
        "size" => 5000000,
        "stored_date" => "2024-01-13T00:00:00.000000",
        "status" => "UPLOADED",
        "current_location" => @location_uuid
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
end
