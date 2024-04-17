require "semantic_logger"

require_relative "lib/config"
require_relative "lib/remote_client"

SemanticLogger.add_appender(io: $stderr, formatter: :color)
config = Config::ConfigService.from_file(File.join(".", "config", "config.yml"))
SemanticLogger.default_level = config.settings.log_level

class RestoreError < StandardError
end

class RestoreJob
  include SemanticLogger::Loggable

  def initialize(config:, base_path: "umich.edu")
    aws_config = config.aptrust.remote.settings
    if config.aptrust.remote.type != :aptrust
      raise RestoreError, "The APTrust remote type must be \"aptrust\" to use the restore script."
    end
    AwsS3RemoteClient.update_config(
      access_key_id: aws_config.access_key_id,
      secret_access_key: aws_config.secret_access_key
    )
    @base_path = base_path
    @restore_dir = config.settings.restore_dir
    @aptrust_client = AwsS3RemoteClient.from_config(
      region: aws_config.region,
      bucket_name: aws_config.restore_bucket
    )
    @staging_client = RemoteClient::RemoteClientFactory.from_config(
      type: config.dark_blue.staging.type,
      settings: config.dark_blue.staging.settings
    )
  end

  def send_to_staging
    logger.info("Sending all files in restore directory to #{staging_client.remote_text}")
    Dir[@restore_path].each do |bag_path|
      logger.debug(bag_path)
      @staging_client.send_file(local_file_path: bag_path)
    end
  end

  def restore_all
    logger.info("Retrieving all files in #{aptrust_client.remote_text}from path: #{@base_path}")
    @aptrust_client.retrieve_from_path(remote_path: @base_path, local_path: @restore_dir)
  end

  def restore_bags(bag_identifiers)
    bag_identifiers.each do |bag_identifier|
      @aptrust_client.retrieve_file(
        remote_path: [@base_path, bag_identifier, ".tar"].join(""),
        local_dir_path: @restore_dir
      )
    end
  end
end

RestoreOptions = Struct.new(:bags)

class RestoreParser
  def self.parse(options)
    args = RestoreOptions.new(options)
    opt_parser = OptionParser.new do |parser|
      parser.banner = "Usage: restore.rb [options]"
      parser.on(
        "-bBAGS",
        "--bags=BAGS",
        Array,
        "List of comma-separated bag identifiers"
      ) do |b|
        args.bags = b
      end
      parser.on("-s", "--send", TrueClass, "Flag determing whether to send bags to staging") do
        args.send = s
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

restore_job = RestoreJob.new(config)

options = RestoreParser.parse ARGV
if options.bags.length > 0
  restore_job.restore_bags(bag_identifiers)
else
  restore_job.restore_all
end
restore_job.send_to_staging if options.send
