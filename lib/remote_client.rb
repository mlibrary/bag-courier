require "bundler/setup"

require "aws-sdk-s3"
require "sftp"

require_relative "../services"

module RemoteClient
  class RemoteClientError < StandardError
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

    def retrieve_from_path(local_path:, remote_path: nil)
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
      file_name = File.basename(local_file_path)
      new_remote_path = File.join(@base_dir_path, remote_path || "")
      logger.debug("Sending file \"#{file_name}\" to \"#{new_remote_path}\"")
      FileUtils.cp(local_file_path, File.join(new_remote_path, file_name))
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      file_name = File.basename(remote_file_path)
      logger.debug("Retrieving file \"#{file_name}\" and saving to \"#{local_dir_path}\"")
      FileUtils.cp(
        File.join(@base_dir_path, remote_file_path),
        File.join(local_dir_path, file_name)
      )
    end

    # Retrieves recursively all files and directories found at remote_path
    def retrieve_from_path(local_path:, remote_path: nil)
      full_path = File.join(@base_dir_path, remote_path || "")
      logger.debug("Full remote path: #{full_path}")
      file_paths = Dir[full_path + "/*"]
      logger.debug("Files found at path \"#{remote_path}\" in remote: #{file_paths}")

      # Copies over current data
      FileUtils.cp_r(full_path, local_path)
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

    attr_reader :bucket

    def initialize(bucket)
      @bucket = bucket
    end

    def self.from_config(region:, bucket_name:)
      s3 = Aws::S3::Resource.new(region: region)
      bucket = s3.bucket(bucket_name)
      new(bucket)
    end

    def remote_text
      "AWS S3 remote location in bucket \"#{@bucket.name}\""
    end

    def send_file(local_file_path:, remote_path: nil)
      file_name = File.basename(local_file_path)
      logger.debug("File name: #{file_name}")
      object_key = remote_path ? File.join(remote_path, file_name) : file_name
      logger.debug("Sending file \"#{file_name}\" to \"#{remote_path}\"")
      aws_object = @bucket.object(object_key)
      aws_object.upload_file(local_file_path, progress_callback: UPLOAD_PROGRESS)
    rescue Aws::S3::MultipartUploadError, Aws::S3::Errors::ServiceError => e
      raise RemoteClientError, "Error occurred while uploading file to AWS S3: #{e.full_message}"
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      file_name = File.basename(remote_file_path)
      logger.debug("Retrieving file \"#{file_name}\" and saving to \"#{local_dir_path}\"")
      aws_object = @bucket.object(remote_file_path)
      aws_object.download_file(File.join(local_dir_path, file_name))
    rescue Aws::S3::Errors::ServiceError => e
      raise RemoteClientError, "Error occurred while downloading file from AWS S3: #{e.full_message}"
    end

    def get_files_at_path(remote_path = nil)
      file_paths = @bucket.objects({prefix: remote_path}).map { |o| o.key }
      logger.debug("Files found at path \"#{remote_path}\" in remote: #{file_paths}")
      file_paths
    end
    private :get_files_at_path

    # Retrieves files at remote_path, creating directories as necessary.
    def retrieve_from_path(local_path:, remote_path: nil)
      logger.debug("Retrieving files (and parent directories) and placing at #{local_path}")
      get_files_at_path(remote_path).each do |remote_file_path|
        dir_path = File.join(local_path, File.dirname(remote_file_path))
        FileUtils.mkdir_p(dir_path) unless Dir.exist?(dir_path)
        retrieve_file(remote_file_path: remote_file_path, local_dir_path: dir_path)
      end
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
      @client.put(local_file_path, remote_path || ".")
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      @client.get(remote_file_path, local_dir_path)
    end

    def retrieve_from_path(local_path:, remote_path: nil)
      @client.get_r(remote_path || ".", local_path)
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
      end
    end
  end
end
