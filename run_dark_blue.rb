require "semantic_logger"
require "sequel"

require_relative "lib/config"

SemanticLogger.add_appender(io: $stderr, formatter: :color)
config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))
SemanticLogger.default_level = config.settings.log_level

DB = config.database && Sequel.connect(
  adapter: "mysql2",
  host: config.database.host,
  port: config.database.port,
  database: config.database.database,
  user: config.database.user,
  password: config.database.password,
  fractional_seconds: true
)

require_relative "lib/archivematica"
require_relative "lib/bag_repository"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"
require_relative "lib/remote_client"
require_relative "lib/repository_package_repository"
require_relative "lib/status_event_repository"

class DarkBlueJob
  include SemanticLogger::Loggable

  def initialize(config)
    @package_repo = RepositoryPackageRepository::RepositoryPackageRepositoryFactory.for(use_db: DB)
    @dispatcher = Dispatcher::APTrustDispatcher.new(
      settings: config.settings,
      repository: config.repository,
      target_client: RemoteClient::RemoteClientFactory.from_config(
        type: config.target_remote.type,
        settings: config.target_remote.settings
      ),
      status_event_repo: StatusEventRepository::StatusEventRepositoryFactory.for(use_db: DB),
      bag_repo: BagRepository::BagRepositoryFactory.for(use_db: DB)
    )
    @arch_configs = config.dark_blue.archivematicas
    @object_size_limit = config.settings.object_size_limit
  end

  def process
    @arch_configs.each do |arch_config|
      logger.info("Archivematica instance: #{arch_config.name}")
      api_config = arch_config.api
      arch_api = Archivematica::ArchivematicaAPI.from_config(
        base_url: api_config.base_url,
        api_key: api_config.api_key,
        username: api_config.username
      )
      remote_config = arch_config.remote
      remote_client = RemoteClient::RemoteClientFactory.from_config(
        type: remote_config.type,
        settings: remote_config.settings
      )

      max_updated_at = @package_repo.get_max_updated_at_for_repository(arch_config.repository_name)

      repository_packages = Archivematica::ArchivematicaService.new(
        name: arch_config.name,
        api: arch_api,
        location_uuid: api_config.location_uuid,
        stored_date: max_updated_at&.iso8601,
        object_size_limit: @object_size_limit
      ).get_repository_packages
      logger.debug(repository_packages)

      repository_packages.each do |package|
        logger.debug(package)
        created = @package_repo.create(
          identifier: package.metadata.id,
          repository_name: arch_config.repository_name,
          updated_at: package.stored_time
        )
        if !created
          @package_repo.update_updated_at(
            identifier: package.metadata.id,
            updated_at: package.stored_time
          )
        end

        courier = @dispatcher.dispatch(
          object_metadata: package.metadata,
          data_transfer: DataTransfer::RemoteClientDataTransfer.new(
            remote_client: remote_client,
            remote_path: package.remote_path
          ),
          context: package.context
        )
        courier.deliver
      end
    end

    logger.info("Events")
    @dispatcher.status_event_repo.get_all.each do |e|
      logger.info(e)
    end
  end
end

DarkBlueJob.new(config).process
