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
require_relative "lib/status_event_repository"

class DarkBlueJob
  include SemanticLogger::Loggable

  def initialize(config)
    @dispatcher = Dispatcher::APTrustDispatcher.new(
      settings: config.settings,
      repository: config.repository,
      target_client: RemoteClient::RemoteClientFactory.from_config(
        type: config.target_remote.type,
        settings: config.target_remote.settings
      ),
      status_event_repo: StatusEventRepository::StatusEventRepositoryFactory.for(DB),
      bag_repo: BagRepository::BagRepositoryFactory.for(DB)
    )
    @arch_configs = config.dark_blue.archivematicas
    @object_size_limit = config.settings.object_size_limit
  end

  def process
    digital_objects = []
    @arch_configs.each do |arch_config|
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

      digital_objects = Archivematica::ArchivematicaService.new(
        name: arch_config.name,
        api: arch_api,
        location_uuid: api_config.location_uuid,
        object_size_limit: @object_size_limit
      ).get_digital_objects
      logger.debug(digital_objects)

      digital_objects.each do |obj|
        courier = @dispatcher.dispatch(
          object_metadata: obj.metadata,
          data_transfer: DataTransfer::RemoteClientDataTransfer.new(
            remote_client: remote_client,
            remote_path: obj.remote_path
          ),
          context: obj.context
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
