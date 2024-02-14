require "semantic_logger"

require_relative "lib/archivematica"
require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"
require_relative "lib/remote_client"

SemanticLogger.add_appender(io: $stderr, formatter: :color)

config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))
SemanticLogger.default_level = config.settings.log_level

class DarkBlueJob
  include SemanticLogger::Loggable

  def initialize(config)
    @dispatcher = Dispatcher::APTrustDispatcher.new(
      settings: config.settings,
      repository: config.repository,
      target_client: RemoteClient::RemoteClientFactory.from_config(
        type: config.target_remote.type,
        settings: config.target_remote.settings
      )
    )
    @source_dir = config.settings.source_dir
    @arch_configs = config.dark_blue.archivematicas
    @object_size_limit = config.settings.object_size_limit
  end

  def process_arch_instance(arch_name:, arch_api:, location_uuid:, source_client:)
    packages = arch_api.get_packages(location_uuid: location_uuid)
    selected_packages = packages.select { |p| p.size < @object_size_limit }
    logger.info("Number of packages below object size limit: #{selected_packages.length}")

    selected_packages.each do |package|
      logger.info(package)
      inner_bag_dir_name = File.basename(package.path)
      logger.info("Inner bag name: #{inner_bag_dir_name}")
      ingest_dir_name = inner_bag_dir_name.gsub("-" + package.uuid, "")
      logger.info("Directory name on Archivematica ingest: #{ingest_dir_name}")

      # Copy file to local source directory, using SFTP or shared mount
      source_client.retrieve_from_path(
        remote_path: package.path,
        local_path: @source_dir
      )
      # Extract metadata if possible?
      object_metadata = Dispatcher::ObjectMetadata.new(
        id: package.uuid,
        creator: "Not available",
        description: "Not available",
        title: "#{package.uuid} / #{ingest_dir_name}"
      )

      # Dispatch courier and deliver
      inner_bag_source_path = File.join(@source_dir, inner_bag_dir_name)
      courier = @dispatcher.dispatch(
        object_metadata: object_metadata,
        data_transfer: DataTransfer::DirDataTransfer.new(inner_bag_source_path),
        context: arch_name
      )
      courier.deliver
    end
  end

  def process
    @arch_configs.each do |arch_config|
      arch_api = Archivematica::ArchivematicaAPI.from_config(
        base_url: arch_config.api.base_url,
        api_key: arch_config.api.api_key,
        username: arch_config.api.username
      )
      source_client = RemoteClient::RemoteClientFactory.from_config(
        type: arch_config.remote.type,
        settings: arch_config.remote.settings
      )
      process_arch_instance(
        arch_name: arch_config.name,
        arch_api: arch_api,
        location_uuid: arch_config.api.location_uuid,
        source_client: source_client
      )
    end
    logger.info("Events")
    @dispatcher.status_event_repo.get_all.each do |e|
      logger.info(e)
    end
  end
end

DarkBlueJob.new(config).process
