require "logger"

require "faraday"
require "faraday/retry"

LOGGER = Logger.new($stdout)

module Archivematica
  Package = Struct.new(
    :uuid,
    :path,
    :size,
    :stored_date,
    keyword_init: true
  )

  class ArchivematicaAPIError < StandardError
  end

  class ArchivematicaAPI
    @@location_endpoint = "location/"
    @@packages_endpoint = "file/"

    attr_reader :base_url

    def initialize(conn, api_prefix: "/api/v2/")
      @api_prefix = api_prefix
      @conn = conn
    end

    def self.from_config(base_url:, username:, api_key:, api_prefix: "/api/v2/")
      conn = Faraday.new(
        url: "#{base_url}#{api_prefix}",
        headers: {"Authorization" => "ApiKey #{username}:#{api_key}"}
      ) do |builder|
        builder.request :retry
        builder.response :raise_error
      end
      new(conn, api_prefix: api_prefix)
    end

    def get(url, params = nil)
      resp = @conn.get(url, params)
      JSON.parse(resp.body)
    rescue Faraday::Error => e
      raise ArchivematicaAPIError, (
        "Error occurred while interacting with Archivematica API. " \
        "Error type: #{e.class}; " \
        "status code: #{e.response_status}; " \
        "body: #{e.response_body}"
      )
    end

    def get_next_url(meta)
      (meta.key?("next") && meta["next"].is_a?(String)) ?
        meta["next"].gsub(@api_prefix, "") : nil
    end
    private :get_next_url

    def get_objects_from_pages(url, params = nil)
      no_more_pages = false
      current_url = url
      results = []
      LOGGER.debug("Starting URL: #{current_url}")
      until no_more_pages
        data = get(current_url, params)
        results += data["objects"]
        meta = data["meta"]
        LOGGER.debug("Meta: #{meta}")
        next_url = get_next_url(meta)
        if next_url.nil?
          no_more_pages = true
        else
          current_url = next_url
        end
      end
      results
    end
    private :get_objects_from_pages

    def get_packages(location_uuid:)
      objects = get_objects_from_pages(@@packages_endpoint, {
        "current_location" => location_uuid
      })
      LOGGER.debug("Total number of objects found: #{objects.length}")
      uploaded_objects = objects.select { |o| o["status"] == "UPLOADED" }
      packages = uploaded_objects.map do |o|
        Package.new(
          uuid: o["uuid"],
          path: o["current_full_path"],
          size: o["size"],
          stored_date: o["stored_date"]
        )
      end
      LOGGER.info(
        "Number of packages found in target location with UPLOADED status: " +
        packages.length.to_s
      )
      packages
    end
  end
end
