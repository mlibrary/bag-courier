require "semantic_logger"

require_relative "lib/archivematica"
require_relative "lib/config"
require_relative "lib/data_transfer"
require_relative "lib/digital_object"
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
    @arch_configs = config.dark_blue.archivematicas
    @source_dir = config.settings.source_dir
    @object_size_limit = config.settings.object_size_limit
  end

  def process
    digital_objects = []
    @arch_configs.each do |arch_config|
      digital_objects += Archivematica::ArchivematicaService.from_config(
        config: arch_config,
        source_dir: @source_dir,
        object_size_limit: @object_size_limit
      ).get_digital_objects
    end
    logger.debug(digital_objects)

    digital_objects.each do |digital_object|
      courier = @dispatcher.dispatch(
        object_metadata: digital_object.metadata,
        data_transfer: DataTransfer::DirDataTransfer.new(digital_object.path),
        context: digital_object.context
      )
      courier.deliver
    end

    logger.info("Events")
    @dispatcher.status_event_repo.get_all.each do |e|
      logger.info(e)
    end
  end
end

DarkBlueJob.new(config).process
