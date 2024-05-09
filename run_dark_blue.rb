require "optparse"

require_relative "services"

config = S.config
DB = config.database && S.dbconnect

require_relative "lib/archivematica"
require_relative "lib/bag_repository"
require_relative "lib/bag_validator"
require_relative "lib/data_transfer"
require_relative "lib/dispatcher"
require_relative "lib/metrics"
require_relative "lib/remote_client"
require_relative "lib/repository_package_repository"
require_relative "lib/status_event_repository"

class DarkBlueError < StandardError
end

class DarkBlueJob
  include DarkBlueLogger

  module ExtraBagInfoData
    CONTENT_TYPE_KEY = "Dark-Blue-Content-Type"
    LOCATION_UUID_KEY = "Archivematica-Location-UUID"
  end

  def initialize(config)
    @package_repo = RepositoryPackageRepository::RepositoryPackageRepositoryFactory.for(use_db: DB)
    @bag_repo = BagRepository::BagRepositoryFactory.for(use_db: DB)
    @status_event_repo = S.status_event_repo

    @settings_config = config.settings
    @repository_config = config.repository
    @aptrust_config = config.aptrust

    @arch_configs = config.dark_blue.archivematicas
    @object_size_limit = config.settings.object_size_limit
  end

  def create_dispatcher(context:, extra_bag_info_data:)
    Dispatcher::APTrustDispatcher.new(
      settings: @settings_config.workflow,
      repository: @repository_config,
      target_client: RemoteClient::RemoteClientFactory.from_config(
        type: @aptrust_config.remote.type,
        settings: @aptrust_config.remote.settings
      ),
      status_event_repo: @status_event_repo,
      bag_repo: @bag_repo,
      context: context,
      extra_bag_info_data: extra_bag_info_data
    )
  end

  def prepare_arch_service(name:, api_config:)
    Archivematica::ArchivematicaService.new(
      name: name,
      api: Archivematica::ArchivematicaAPI.from_config(
        base_url: api_config.base_url,
        api_key: api_config.api_key,
        username: api_config.username
      ),
      location_uuid: api_config.location_uuid
    )
  end
  private :prepare_arch_service

  def create_extra_bag_info_data(content_type:, location_uuid:)
    {
      ExtraBagInfoData::CONTENT_TYPE_KEY => content_type,
      ExtraBagInfoData::LOCATION_UUID_KEY => location_uuid
    }
  end

  def deliver_package(dispatcher:, package_data:, remote_client:)
    courier = dispatcher.dispatch(
      object_metadata: package_data.metadata,
      data_transfer: DataTransfer::RemoteClientDataTransfer.new(
        remote_client: remote_client,
        remote_path: package_data.remote_path
      ),
      validator: InnerBagValidator.new(package_data.dir_name)
    )
    logger.measure_info("Delivered package #{package_data.metadata.id}.") do
      courier.deliver
    end
  end
  private :deliver_package

  def redeliver_package(identifier)
    logger.info("Re-delivering Archivematica package #{identifier}")
    package = @package_repo.get_by_identifier(identifier)
    unless package
      message = "No repository package was found with identifier #{identifier}"
      raise DarkBlueError, message
    end

    arch_config = @arch_configs.find { |ac| ac.repository_name == package.repository_name }
    unless arch_config
      message = "No configured Archivematica instance was found " \
        "with name #{package.repository_name}."
      raise DarkBlueError, message
    end

    extra_bag_info_data = create_extra_bag_info_data(
      content_type: arch_config.name, location_uuid: arch_config.api.location_uuid
    )
    dispatcher = create_dispatcher(context: arch_config.name, extra_bag_info_data: extra_bag_info_data)

    arch_service = prepare_arch_service(name: arch_config.name, api_config: arch_config.api)
    package_data = arch_service.get_package_data_object(package.identifier)
    unless package_data
      message = "No package with identifier #{package.identifier} was found " \
        "in #{arch_config.name} Archivematica instance."
      raise DarkBlueError, message
    end

    source_remote_client = RemoteClient::RemoteClientFactory.from_config(
      type: arch_config.remote.type,
      settings: arch_config.remote.settings
    )
    deliver_package(
      dispatcher: dispatcher, package_data: package_data, remote_client: source_remote_client
    )
  end
  private :redeliver_package

  def redeliver_packages(package_identifiers)
    package_identifiers.each { |pi| redeliver_package(pi) }
  end

  def process_arch_instance(arch_config)
    logger.info(
      "Starting search and delivery process for new packages " \
      "in Archivematica instance #{arch_config.name}"
    )
    extra_bag_info_data = create_extra_bag_info_data(
      content_type: arch_config.name, location_uuid: arch_config.api.location_uuid
    )
    dispatcher = create_dispatcher(context: arch_config.name, extra_bag_info_data: extra_bag_info_data)

    arch_service = prepare_arch_service(name: arch_config.name, api_config: arch_config.api)
    source_remote_client = RemoteClient::RemoteClientFactory.from_config(
      type: arch_config.remote.type,
      settings: arch_config.remote.settings
    )

    max_updated_at = @package_repo.get_max_updated_at_for_repository(arch_config.repository_name)
    object_size_limit = @settings_config.object_size_limit
    num_objects_per_repo = @settings_config.num_objects_per_repo
    package_data_objs = arch_service.get_package_data_objects(
      stored_date: max_updated_at,
      **(object_size_limit ? {package_filter: Archivematica::SizePackageFilter.new(object_size_limit)} : {})
    )

    if num_objects_per_repo && package_data_objs.length > num_objects_per_repo
      package_data_objs = package_data_objs.take(num_objects_per_repo)
    end

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
        dispatcher: dispatcher, package_data: package_data, remote_client: source_remote_client
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

start_time, end_time = Metrics::Timer.time_processing {
  if options.packages.length > 0
    dark_blue_job.redeliver_packages(options.packages)
  else
    dark_blue_job.process
  end
}
metrics = Metrics::MetricsProvider.new(
  start_time: start_time,
  end_time: end_time,
  status_event_repo: S.status_event_repo,
  push_gateway_url: config.metrics.push_gateway_url
)
metrics.set_all_metrics
