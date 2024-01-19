require "logger"

require "faraday"

LOGGER = Logger.new($stdout)

module Archivematica
  Package = Struct.new(
    :uuid,
    :path,
    :size,
    :stored_date,
    keyword_init: true
  )

  class ArchivematicaAPI
    @@location_endpoint = "location/"
    @@packages_endpoint = "file/"

    attr_reader :base_url

    def initialize(base_url:, username:, api_key:, api_prefix: "/api/v2/")
      @api_prefix = api_prefix
      @conn = Faraday.new(
        url: "#{base_url}#{api_prefix}",
        headers: {"Authorization" => "ApiKey #{username}:#{api_key}"}
      )
    end

    def get_next_url(meta)
      (meta.key?("next") && meta["next"].is_a?(String)) ?
        meta["next"].gsub(@api_prefix, "") : nil
    end
    private :get_next_url

    def get_objects_from_pages(url)
      no_more_pages = false
      current_url = url
      results = []
      LOGGER.debug("Starting URL: #{current_url}")
      until no_more_pages
        resp = @conn.get(current_url)
        data = JSON.parse(resp.body)
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

    def get_packages(uuid)
      objects = get_objects_from_pages(@@packages_endpoint)
      LOGGER.debug("Total number of objects found: #{objects.length}")
      filtered_objects = objects.select do |o|
        location_url = "#{@api_prefix}#{@@location_endpoint}#{uuid}/"
        o["current_location"] == location_url && o["status"] == "UPLOADED"
      end
      packages = filtered_objects.map do |o|
        Package.new(
          uuid: o["uuid"],
          path: o["current_full_path"],
          size: o["size"],
          stored_date: o["stored_date"]
        )
      end
      LOGGER.debug("Number of packages found in target location with UPLOADED status: #{packages.length}")
      packages
    end
  end
end
