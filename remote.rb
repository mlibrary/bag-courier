require "aws-sdk-s3"

module Remote
  class RemoteError < StandardError
  end

  class RemoteBase
    def upload_file(file_path)
      raise NotImplementedError
    end

    def download_file(file_path, source_file_name = nil)
      raise NotImplementedError
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

    def upload_file(source_file_path)
      aws_object = @bucket.object(File.basename(source_file_path))
      aws_object.upload_file(source_file_path)
    rescue Aws::S3::Errors::ServiceError => e
      raise RemoteError, "Error occurred while uploading file to AWS S3: #{e}"
    end

    def download_file(remote_file_path, target_file_path)
      aws_object = @bucket.object(remote_file_path)
      aws_object.download_file(target_file_path)
    rescue Aws::S3::Errors::ServiceError => e
      raise RemoteError, "Error occurred while downloading file from AWS S3: #{e}"
    end
  end
end
