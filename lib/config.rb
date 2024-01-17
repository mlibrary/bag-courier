require "logger"
require "yaml"

LOGGER = Logger.new($stdout)

module Config
  SettingsConfig = Struct.new(
    :dry_run,
    :working_dir,
    :export_dir
  )

  TestConfig = Struct.new(
    :work_source_dir
  )

  RepositoryConfig = Struct.new(
    :name,
    :description,
    keyword_init: true
  )

  AptrustAwsRemoteConfig = Struct.new(
    :region,
    :receiving_bucket,
    :restore_bucket,
    :access_key_id,
    :secret_access_key,
    keyword_init: true
  )

  FileSystemRemoteConfig = Struct.new(
    :remote_path,
    keyword_init: true
  )

  RemoteConfig = Struct.new(
    :type,
    :settings,
    keyword_init: true
  )

  Config = Struct.new(
    :settings,
    :test,
    :repository,
    :remote,
    keyword_init: true
  )

  class ConfigError < StandardError
  end

  class ConfigService
    def self.raise_error(key, value)
      raise ConfigError, "Value for \"#{key}\" is not valid: #{value}"
    end

    def self.verify_string(key, value)
      if !value.is_a?(String)
        raise_error(key, value)
      end
      value
    end

    def self.to_boolean(value)
      case value
      when true, "true", "1"
        true
      when false, "false", "0"
        false
      else
        raise TypeError, "Value \"#{value}\" could not be converted to true or false."
      end
    end

    def self.verify_boolean(key, value)
      if ![true, false].include?(value)
        raise_error(key, value)
      end
      value
    end

    def self.read_data_from_file(yaml_path)
      LOGGER.debug("yaml_path=#{yaml_path}")
      YAML.safe_load_file(yaml_path)
    end

    # TO DO
    # Support config from environment?

    def self.create_config(data)
      LOGGER.debug(data)
      remote_type = verify_string("RemoteType", data["RemoteType"]).to_sym

      Config.new(
        settings: SettingsConfig.new(
          dry_run: verify_boolean("DryRun", to_boolean(data["DryRun"])),
          working_dir: verify_string("WorkingDir", data["WorkingDir"]),
          export_dir: verify_string("ExportDir", data["ExportDir"])
        ),
        test: TestConfig.new(
          work_source_dir: verify_string("TestSourceDir", data["TestSourceDir"])
        ),
        repository: RepositoryConfig.new(
          name: verify_string("Repository", data["Repository"]),
          description: verify_string("RepositoryDescription", data["RepositoryDescription"])
        ),
        remote: RemoteConfig.new(
          type: remote_type,
          settings: (
            case remote_type
            when :aptrust
              AptrustAwsRemoteConfig.new(
                region: verify_string("BucketRegion", data["BucketRegion"]),
                receiving_bucket: verify_string("ReceivingBucket", data["ReceivingBucket"]),
                restore_bucket: verify_string("RestoreBucket", data["RestoreBucket"]),
                access_key_id: verify_string("AwsAccessKeyId", data["AwsAccessKeyId"]),
                secret_access_key: verify_string("AwsSecretAccessKey", data["AwsSecretAccessKey"])
              )
            when :file_system
              FileSystemRemoteConfig.new(
                remote_path: verify_string("FileSystemRemotePath", data["FileSystemRemotePath"])
              )
            else
              raise ConfigError, "Remote type #{remote_type} is not supported"
            end
          )
        )
      )
    end

    def self.from_file(yaml_path)
      create_config(read_data_from_file(yaml_path))
    end
  end
end
