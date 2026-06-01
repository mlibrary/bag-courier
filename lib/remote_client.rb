require "bundler/setup"

require "pathname"
require "tmpdir"

require "aws-sdk-s3"
require "sftp"

require_relative "../services"

module RemoteClient
  class RemoteClientError < StandardError
  end

  class PathValidator
    def self.ensure_not_nil(path)
      if path.nil?
        raise RemoteClientError, "Path must not be nil."
      end
    end

    def self.ensure_not_empty(path)
      if path.empty?
        raise RemoteClientError, "Path must not be empty."
      end
    end

    def self.ensure_present(path)
      self.ensure_not_nil(path)
      self.ensure_not_empty(path)
    end

    def self.ensure_relative(path)
      if path.start_with?("/")
        raise RemoteClientError, "Path must not start with \"/\"; path provided: #{path}"
      end
    end

    def self.ensure_no_traversal(path)
      Pathname.new(path).each_filename do |segment|
        if [".", ".."].include?(segment.strip)
          message = "Path must not include segments of \".\" or \"..\"; path provided: #{path}"
          raise RemoteClientError, message
        end
      end
    end

    def self.ensure_safe(path)
      self.ensure_present(path)
      self.ensure_relative(path)
      self.ensure_no_traversal(path)
    end
  end

  class RemoteClientBase
    def remote_text
      raise NotImplementedError
    end

    def send_file(local_file_path:, remote_path: nil)
      raise NotImplementedError
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      raise NotImplementedError
    end

    def retrieve_from_path(local_path:, remote_path:)
      raise NotImplementedError
    end
  end

  class FileSystemRemoteClient < RemoteClientBase
    include DarkBlueLogger

    def initialize(base_dir_path)
      @base_dir_path = base_dir_path
    end

    def remote_text
      "file system remote location at \"#{@base_dir_path}\""
    end

    def send_file(local_file_path:, remote_path: nil)
      PathValidator.ensure_present(local_file_path)
      if !remote_path.nil?
        PathValidator.ensure_not_empty(remote_path)
        PathValidator.ensure_relative(remote_path)
        PathValidator.ensure_no_traversal(remote_path)
      end

      file_name = File.basename(local_file_path)
      new_remote_path = !remote_path.nil? ? File.join(@base_dir_path, remote_path) : @base_dir_path
      logger.debug("Sending file \"#{file_name}\" to \"#{new_remote_path}\"")
      FileUtils.cp(local_file_path, File.join(new_remote_path, file_name))
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      PathValidator.ensure_safe(remote_file_path)
      PathValidator.ensure_present(local_dir_path)

      file_name = File.basename(remote_file_path)
      logger.debug("Retrieving file \"#{file_name}\" and saving to \"#{local_dir_path}\"")
      FileUtils.cp(
        File.join(@base_dir_path, remote_file_path),
        File.join(local_dir_path, file_name)
      )
    end

    # Retrieves recursively all files and directories found at remote_path
    def retrieve_from_path(local_path:, remote_path:)
      PathValidator.ensure_present(local_path)
      PathValidator.ensure_safe(remote_path)

      full_remote_path = File.join(@base_dir_path, remote_path)
      logger.debug("Full remote path: #{full_remote_path}")
      file_paths = Dir[full_remote_path + "/*"]
      relative_file_paths = file_paths.map { |p| p.delete_prefix(full_remote_path) }
      logger.debug("Number of files found at path \"#{remote_path}\" in remote: #{relative_file_paths.size}")
      logger.debug("First 10 file paths found: #{file_paths.take(10)}")

      # Copies over current data
      FileUtils.cp_r(full_remote_path, local_path)
      logger.debug("Retrieving files (and directories) and placing at \"#{local_path}\"")
    end
  end

  class AwsS3RemoteClient < RemoteClientBase
    include DarkBlueLogger

    UPLOAD_PROGRESS = proc do |bytes, totals|
      percentage = (100.0 * bytes.sum / totals.sum).round(2)
      logger.debug("Progress: #{bytes.sum} / #{totals.sum} bytes; #{percentage} %")
    end

    def self.update_config(access_key_id:, secret_access_key:)
      Aws.config.update(
        credentials: Aws::Credentials.new(access_key_id, secret_access_key)
      )
    end

    attr_reader :bucket, :transfer_manager

    def initialize(bucket:, transfer_manager:)
      @bucket = bucket
      @transfer_manager = transfer_manager
    end

    def self.from_config(region:, bucket_name:)
      s3 = Aws::S3::Resource.new(region: region)
      bucket = s3.bucket(bucket_name)
      transfer_manager = Aws::S3::TransferManager.new(
        client: Aws::S3::Client.new(region: region)
      )
      new(bucket: bucket, transfer_manager: transfer_manager)
    end

    def remote_text
      "AWS S3 remote location in bucket \"#{@bucket.name}\""
    end

    def send_file(local_file_path:, remote_path: nil)
      PathValidator.ensure_present(local_file_path)
      if !remote_path.nil?
        PathValidator.ensure_not_empty(remote_path)
        PathValidator.ensure_relative(remote_path)
        PathValidator.ensure_no_traversal(remote_path)
      end

      file_name = File.basename(local_file_path)
      logger.debug("File name: #{file_name}")
      object_key = !remote_path.nil? ? File.join(remote_path, file_name) : file_name
      logger.debug("Sending file \"#{file_name}\" to \"#{remote_path}\"")
      @transfer_manager.upload_file(
        local_file_path,
        bucket: @bucket.name,
        key: object_key,
        progress_callback: UPLOAD_PROGRESS
      )
    rescue Aws::S3::MultipartUploadError, Aws::S3::Errors::ServiceError => e
      raise RemoteClientError, "Error occurred while uploading file to AWS S3: #{e.full_message}"
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      PathValidator.ensure_safe(remote_file_path)
      PathValidator.ensure_present(local_dir_path)

      file_name = File.basename(remote_file_path)
      logger.debug("Retrieving file \"#{file_name}\" and saving to \"#{local_dir_path}\"")
      @transfer_manager.download_file(
        File.join(local_dir_path, file_name),
        bucket: @bucket.name,
        key: remote_file_path
      )
    rescue Aws::S3::MultipartDownloadError, Aws::S3::Errors::ServiceError => e
      raise RemoteClientError, "Error occurred while downloading file from AWS S3: #{e.full_message}"
    end

    # Retrieves files at remote_path, creating directories as necessary.
    def retrieve_from_path(local_path:, remote_path:)
      PathValidator.ensure_present(local_path)
      # Traversal sequences are checked by the AWS S3 client, so this is preemptive.
      PathValidator.ensure_safe(remote_path)

      sample_file_paths = @bucket.objects(prefix: remote_path).take(10).map(&:key)
      logger.debug("First 10 file paths found: #{sample_file_paths}")
      if sample_file_paths.empty?
        return
      end
      logger.debug("Retrieving content at path #{remote_path} and placing at #{local_path}")

      Dir.mktmpdir do |staging_dir|
        transfer_manager.download_directory(
          staging_dir,
          bucket: @bucket.name,
          s3_prefix: remote_path
        )
        source_path = File.join(staging_dir, remote_path)
        FileUtils.mv(source_path, local_path)
      end
    rescue Aws::S3::DirectoryDownloadError, Aws::S3::Errors::ServiceError => e
      raise RemoteClientError, "Error occurred while downloading directory from AWS S3: #{e.full_message}"
    end

    # Retrieves files in remote, creating directories as necessary.
    def retrieve_all(local_path:)
      PathValidator.ensure_present(local_path)

      logger.debug("Retrieving content in remote and placing at #{local_path}")
      transfer_manager.download_directory(local_path, bucket: @bucket.name)
    rescue Aws::S3::DirectoryDownloadError, Aws::S3::Errors::ServiceError => e
      raise RemoteClientError, "Error occurred while downloading directory from AWS S3: #{e.full_message}"
    end
  end

  class SftpRemoteClient
    def initialize(client:, host:)
      @client = client
      @host = host
    end

    def self.from_config(user:, host:, key_path:)
      SFTP.configure do |config|
        config.host = host
        config.user = user
        config.key_path = key_path
      end
      new(client: SFTP.client, host: host)
    end

    def remote_text
      "SFTP remote location at \"#{@host}\""
    end

    def send_file(local_file_path:, remote_path: nil)
      PathValidator.ensure_present(local_file_path)
      if !remote_path.nil?
        PathValidator.ensure_not_empty(remote_path)
      end

      @client.put(local_file_path, remote_path || ".")
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      PathValidator.ensure_present(remote_file_path)
      PathValidator.ensure_present(local_dir_path)

      @client.get(remote_file_path, local_dir_path)
    end

    def retrieve_from_path(local_path:, remote_path:)
      PathValidator.ensure_present(local_path)
      PathValidator.ensure_present(remote_path)

      @client.get_r(remote_path, local_path)
    end
  end

  class RemoteClientFactory
    def self.from_config(type:, settings:)
      case type
      when :aptrust
        aws_config = settings
        AwsS3RemoteClient.update_config(
          access_key_id: aws_config.access_key_id,
          secret_access_key: aws_config.secret_access_key
        )
        AwsS3RemoteClient.from_config(
          region: aws_config.region,
          bucket_name: aws_config.receiving_bucket
        )
      when :file_system
        FileSystemRemoteClient.new(settings.remote_path)
      when :sftp
        SftpRemoteClient.from_config(
          host: settings.host,
          user: settings.user,
          key_path: settings.key_path
        )
      else
        raise RemoteClientError, "Unsupported or invalid type: #{type}"
      end
    end
  end
end
