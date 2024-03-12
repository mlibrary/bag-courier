require "faraday"
require "faraday/retry"
require "semantic_logger"

require_relative "repository_package"

module Archivematica
  Package = Struct.new(
    "Package",
    :uuid,
    :path,
    :size,
    :stored_date,
    keyword_init: true
  )

  module PackageStatus
    UPLOADED = "UPLOADED"
    DELETED = "DELETED"
  end

  class ArchivematicaAPIError < StandardError
  end

  class ArchivematicaAPI
    include SemanticLogger::Loggable

    LOCATION_PATH = "location/"
    PACKAGE_PATH = "file/"
    API_V2 = "/api/v2/"

    def initialize(conn, api_prefix: API_V2)
      @conn = conn
      @api_prefix = api_prefix
    end

    def self.from_config(base_url:, username:, api_key:, api_prefix: API_V2)
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
    rescue Faraday::Error => error
      message = "Error occurred while interacting with Archivematica API. " \
        "Error type: #{error.class}; " \
        "status code: #{error.response_status || "none"}; " \
        "body: #{error.response_body || "none"}"
      raise ArchivematicaAPIError, message
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
      logger.debug("Starting URL: #{current_url}")
      until no_more_pages
        data = get(current_url, params)
        results += data["objects"]
        meta = data["meta"]
        logger.debug("Meta: #{meta}")
        next_url = get_next_url(meta)
        if next_url.nil?
          no_more_pages = true
        else
          current_url = next_url
        end
      end
      results
    end

    def get_packages(location_uuid:, stored_date: nil)
      params = {
        "current_location" => location_uuid,
        "status" => PackageStatus::UPLOADED
      }
      if stored_date
        params["stored_date__gt"] = stored_date
      end

      package_objects = get_objects_from_pages(PACKAGE_PATH, params)
      packages = package_objects.map do |o|
        Package.new(
          uuid: o["uuid"],
          path: o["current_full_path"],
          size: o["size"],
          stored_date: o["stored_date"]
        )
      end
      logger.info(
        "Number of packages found in location #{location_uuid} " +
        "with #{PackageStatus::UPLOADED} status" +
        (stored_date ? " and with stored date after #{stored_date}" : "") +
        ": #{packages.length}"
      )
      packages
    end
  end

  class ArchivematicaService
    include SemanticLogger::Loggable

    NA = "Not available"

    attr_reader :name

    def initialize(
      name:,
      api:,
      location_uuid:,
      stored_date:,
      object_size_limit:
    )
      @name = name
      @api = api
      @location_uuid = location_uuid
      @stored_date = stored_date
      @object_size_limit = object_size_limit
    end

    def get_repository_packages
      logger.info("Archivematica instance: #{@name}")
      packages = @api.get_packages(location_uuid: @location_uuid, stored_date: @stored_date)
      selected_packages = packages.select { |p| p.size < @object_size_limit }
      logger.info("Number of packages below object size limit: #{selected_packages.length}")

      selected_packages.map do |package|
        logger.info(package)
        inner_bag_dir_name = File.basename(package.path)
        logger.info("Inner bag name: #{inner_bag_dir_name}")
        ingest_dir_name = inner_bag_dir_name.gsub("-" + package.uuid, "")
        logger.info("Directory name on Archivematica ingest: #{ingest_dir_name}")
        object_metadata = RepositoryPackage::ObjectMetadata.new(
          id: package.uuid,
          title: "#{package.uuid} / #{ingest_dir_name}",
          creator: NA,
          description: NA
        )
        RepositoryPackage::RepositoryPackage.new(
          remote_path: package.path,
          metadata: object_metadata,
          context: @name,
          stored_time: Time.parse(package.stored_date)
        )
      end
    end
  end
end
