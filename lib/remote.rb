require "logger"

require "aws-sdk-s3"

LOGGER = Logger.new($stdout)

module Remote
  class RemoteError < StandardError
  end

  class RemoteBase
    def send_file(local_file_path:, remote_dir_path: "")
      raise NotImplementedError
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      raise NotImplementedError
    end

    def retrieve_dir(local_dir_path:, remote_dir_path: "")
      raise NotImplementedError
    end
  end

  class FileSystemRemote < RemoteBase
    def initialize(base_dir_path)
      @base_dir_path = base_dir_path
    end

    def to_s
      "<FileSystemRemote base_dir_path=\"#{@base_dir_path}\">"
    end

    def send_file(local_file_path:, remote_dir_path: nil)
      file_name = File.basename(local_file_path)
      new_remote_path = File.join(@base_dir_path, remote_dir_path || "")
      LOGGER.debug("Sending file #{file_name} to #{new_remote_path}")
      FileUtils.cp(local_file_path, File.join(new_remote_path, file_name))
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      file_name = File.basename(remote_file_path)
      LOGGER.debug("Retrieving file #{file_name} and saving to #{local_dir_path}")
      FileUtils.cp(
        File.join(@base_dir_path, remote_file_path),
        File.join(local_dir_path, file_name)
      )
    end

    def retrieve_dir(local_dir_path:, remote_dir_path: nil)
      full_path = File.join(@base_dir_path, remote_dir_path || "")
      dir_name = File.basename(full_path)
      file_paths = Dir[full_path + "/*"]
      LOGGER.debug("Files found in directory #{dir_name} in remote: #{file_paths}")

      # Copies over current data
      FileUtils.copy_entry(full_path, File.join(local_dir_path, dir_name))
      LOGGER.debug(
        "Retrieving directory #{dir_name} and saving to #{local_dir_path}"
      )
    end
  end

  class AwsS3Remote < RemoteBase
    def self.update_config(access_key_id, secret_access_key)
      Aws.config.update(
        credentials: Aws::Credentials.new(access_key_id, secret_access_key)
      )
    end

    def initialize(region:, bucket:)
      s3 = Aws::S3::Resource.new(region: region)
      @bucket = s3.bucket(bucket)
    end

    def to_s
      "<AwsS3Remote bucket=\"#{@bucket.name}\">"
    end

    def send_file(local_file_path:, remote_dir_path: nil)
      file_name = File.basename(local_file_path)
      LOGGER.debug("file_name: " + file_name)
      object_key = remote_dir_path ? File.join(remote_dir_path, file_name) : file_name
      aws_object = @bucket.object(object_key)
      aws_object.upload_file(local_file_path)
    rescue Aws::S3::Errors::ServiceError => e
      raise RemoteError, "Error occurred while uploading file to AWS S3: #{e}"
    end

    def retrieve_file(remote_file_path:, local_dir_path:)
      aws_object = @bucket.object(remote_file_path)
      aws_object.download_file(local_dir_path)
    rescue Aws::S3::Errors::ServiceError => e
      raise RemoteError, "Error occurred while downloading file from AWS S3: #{e}"
    end

    # def retrieve_dir(local_dir_path:, remote_dir_path: nil)
    # end
  end
end
