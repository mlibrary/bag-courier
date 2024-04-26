require "optparse"

require_relative "lib/remote_client"
require_relative "services"

class RestoreError < StandardError
end

class RestoreJob
  include DarkBlueLogger

  def initialize(config:, base_path: "umich.edu")
    aws_config = config.aptrust.remote.settings
    if config.aptrust.remote.type != :aptrust
      raise RestoreError, "The APTrust remote type must be \"aptrust\" to use the restore script."
    end
    RemoteClient::AwsS3RemoteClient.update_config(
      access_key_id: aws_config.access_key_id,
      secret_access_key: aws_config.secret_access_key
    )
    @base_path = base_path
    @restore_dir = config.settings.restore_dir
    @aptrust_client = RemoteClient::AwsS3RemoteClient.from_config(
      region: aws_config.region,
      bucket_name: aws_config.restore_bucket
    )
  end

  def restore_all
    logger.info("Retrieving all files in #{@aptrust_client.remote_text} from path: #{@base_path}")
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
      parser.on("-h", "--help", "Prints this help") do
        puts parser
        exit
      end
    end
    opt_parser.parse!(options)
    args
  end
end

restore_job = RestoreJob.new(config: S.config)

options = RestoreParser.parse ARGV
if options.bags.length > 0
  restore_job.restore_bags(bag_identifiers)
else
  restore_job.restore_all
end
