require "logger"
require "yaml"

LOGGER = Logger.new($stdout)

module Config
  RepositoryConfig = Struct.new(
    :name,
    :description,
    keyword_init: true
  )

  APTrustConfig = Struct.new(
    :download_dir,
    :aptrust_api_url,
    :aptrust_api_user,
    :aptrust_api_key,
    :bucket,
    :bucket_region,
    :aws_access_key_id,
    :aws_secret_access_key,
    keyword_init: true
  )

  Config = Struct.new(
    :working_dir,
    :export_dir,
    :test_source_dir,
    :repository,
    :aptrust,
    keyword_init: true
  )

  class ConfigError < StandardError
  end

  class ConfigService
    def self.verify_string(key, value)
      if !value.is_a?(String)
        raise ConfigError, "Value for \"#{key}\" is not valid: #{value}"
      end
      value
    end

    def self.read_config_file(yaml_path)
      LOGGER.debug("yaml_path=#{yaml_path}")
      YAML.safe_load_file(yaml_path)
    end

    # TO DO
    # Support config from environment?

    def self.create_config(data)
      LOGGER.debug(data)

      Config.new(
        working_dir: verify_string("WorkingDir", data["WorkingDir"]),
        export_dir: verify_string("ExportDir", data["ExportDir"]),
        test_source_dir: verify_string("TestSourceDir", data["TestSourceDir"]),
        repository: RepositoryConfig.new(
          name: verify_string("Repository", data["Repository"]),
          description: verify_string("RepositoryDescription", data["RepositoryDescription"])
        ),
        aptrust: APTrustConfig.new(
          download_dir: verify_string("DownloadDir", data["DownloadDir"]),
          aptrust_api_user: verify_string("AptrustApiUser", data["AptrustApiUser"]),
          aptrust_api_url: verify_string("AptrustApiUrl", data["AptrustApiUrl"]),
          aptrust_api_key: verify_string("AptrustApiKey", data["AptrustApiKey"]),
          bucket: verify_string("Bucket", data["Bucket"]),
          bucket_region: verify_string("BucketRegion", data["BucketRegion"]),
          aws_access_key_id: verify_string("AwsAccessKeyId", data["AwsAccessKeyId"]),
          aws_secret_access_key: verify_string("AwsSecretAccessKey", "AwsSecretAccessKey")
        )
      )
    end
  end
end
