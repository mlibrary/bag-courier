require "optparse"

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
require_relative "lib/bag_validator"

class DarkBlueError < StandardError
end

class DarkBlueJob
  include SemanticLogger::Loggable

  def initialize(config)
    @package_repo = RepositoryPackageRepository::RepositoryPackageRepositoryFactory.for(use_db: DB)
    @dispatcher = Dispatcher::APTrustDispatcher.new(
      settings: config.settings,
      repository: config.repository,
      target_client: RemoteClient::RemoteClientFactory.from_config(
        type: config.aptrust.remote.type,
        settings: config.aptrust.remote.settings
      ),
      status_event_repo: StatusEventRepository::StatusEventRepositoryFactory.for(use_db: DB),
      bag_repo: BagRepository::BagRepositoryFactory.for(use_db: DB)
    )
    @arch_configs = config.dark_blue.archivematicas
    @object_size_limit = config.settings.object_size_limit
  end

  def prepare_arch_service(arch_config)
    api_config = arch_config.api
    Archivematica::ArchivematicaService.new(
      name: arch_config.name,
      api: Archivematica::ArchivematicaAPI.from_config(
        base_url: api_config.base_url,
        api_key: api_config.api_key,
        username: api_config.username
      ),
      location_uuid: api_config.location_uuid
    )
  end
  private :prepare_arch_service

  def deliver_package(package_data:, remote_client:, context:)
    courier = @dispatcher.dispatch(
      object_metadata: package_data.metadata,
      data_transfer: DataTransfer::RemoteClientDataTransfer.new(
        remote_client: remote_client,
        remote_path: package_data.remote_path
      ),
      context: context,
      validator: InnerBagValidator.new(package_data.dir_name)
    )
    courier.deliver
  end
  private :deliver_package

  def redeliver_package(package_identifier)
    package = @package_repo.get_by_identifier(package_identifier)
    raise DarkBlueError, "No repository package was found with identifier #{package_identifier}" unless package

    arch_config = @arch_configs.find { |ac| ac.repository_name == package.repository_name }
    raise DarkBlueError, "No configured Archivematica instance by name #{package.repository_name}" unless arch_config

    arch_service = prepare_arch_service(arch_config)
    package_data = arch_service.get_package_data_object(package.identifier)
    if !package_data
      message = "No Archivematica package with identifier #{package.identifier} found in instance #{arch_config.name}"
      raise DarkBlueError, message
    end

    remote_client = RemoteClient::RemoteClientFactory.from_config(
      type: arch_config.remote.type,
      settings: arch_config.remote.settings
    )
    deliver_package(
      package_data: package_data,
      remote_client: remote_client,
      context: arch_config.name
    )
  end
  private :redeliver_package

  def redeliver_packages(package_identifiers)
    package_identifiers.each { |pi| redeliver_package(pi) }
  end

  def process_arch_instance(arch_config)
    arch_service = prepare_arch_service(arch_config)
    remote_config = arch_config.remote
    remote_client = RemoteClient::RemoteClientFactory.from_config(
      type: remote_config.type,
      settings: remote_config.settings
    )

    max_updated_at = @package_repo.get_max_updated_at_for_repository(arch_config.repository_name)
    package_data_objs = arch_service.get_package_data_objects(
      stored_date: max_updated_at,
      **(@object_size_limit ? {package_filter: Archivematica::SizePackageFilter.new(@object_size_limit)} : {})
    )
    package_data_objs.each do |package_data|
      logger.debug(package_data)
      created = @package_repo.create(
        identifier: package_data.metadata.id,
        repository_name: arch_config.repository_name,
        updated_at: package_data.stored_time
      )
      if !created
        @package_repo.update_updated_at(
          identifier: package_data.metadata.id,
          updated_at: package_data.stored_time
        )
      end
      deliver_package(
        package_data: package_data,
        remote_client: remote_client,
        context: arch_config.name
      )
    end
  end

  def process
    @arch_configs.each { |ac| process_arch_instance(ac) }
  end
end

DarkBlueOptions = Struct.new(:packages)

class DarkBlueParser
  def self.parse(options)
    args = DarkBlueOptions.new(options)
    opt_parser = OptionParser.new do |parser|
      parser.banner = "Usage: run_dark_blue.rb [options]"
      parser.on(
        "-pPACKAGES",
        "--packages=PACKAGES",
        Array,
        "List of comma-separated package identifiers"
      ) do |p|
        args.packages = p
      end
      parser.on("-h", "--help", "Prints this help") do
        puts parser
        exit
      end
    end
    opt_parser.parse!(options)
    args
  end
end

dark_blue_job = DarkBlueJob.new(config)

options = DarkBlueParser.parse ARGV
if options.packages.length > 0
  dark_blue_job.redeliver_packages(options.packages)
else
  dark_blue_job.process
end
