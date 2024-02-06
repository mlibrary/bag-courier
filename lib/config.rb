require "logger"
require "yaml"

LOGGER = Logger.new($stdout)

module Config
  SettingsConfig = Struct.new(
    "SettingsConfig",
    :dry_run,
    :working_dir,
    :export_dir
  )

  TestConfig = Struct.new(
    "TestConfig",
    :source_dir
  )

  RepositoryConfig = Struct.new(
    "RepositoryConfig",
    :name,
    :description,
    keyword_init: true
  )

  AptrustAwsRemoteConfig = Struct.new(
    "AptrustAwsRemoteConfig",
    :region,
    :receiving_bucket,
    :restore_bucket,
    :access_key_id,
    :secret_access_key,
    keyword_init: true
  )

  FileSystemRemoteConfig = Struct.new(
    "FileSystemRemoteConfig",
    :remote_path,
    keyword_init: true
  )

  RemoteConfig = Struct.new(
    "RemoteConfig",
    :type,
    :settings,
    keyword_init: true
  )

  SftpRemoteConfig = Struct.new(
    "SftpRemoteConfig",
    :host,
    :user,
    :key_path,
    keyword_init: true
  )

  ArchivematicaConfig = Struct.new(
    "ArchivematicaConfig",
    :username,
    :base_url,
    :api_key,
    :location_uuid,
    keyword_init: true
  )

  Config = Struct.new(
    "Config",
    :settings,
    :test,
    :repository,
    :source_remote,
    :target_remote,
    :archivematica,
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

    def self.create_remote_config(data)
      LOGGER.debug(data)
      type = verify_string("RemoteType", data["RemoteType"]).to_sym
      settings = data["RemoteSettings"]
      RemoteConfig.new(
        type: type,
        settings: (
          case type
          when :aptrust
            AptrustAwsRemoteConfig.new(
              region: verify_string("BucketRegion", settings["BucketRegion"]),
              receiving_bucket: verify_string("ReceivingBucket", settings["ReceivingBucket"]),
              restore_bucket: verify_string("RestoreBucket", settings["RestoreBucket"]),
              access_key_id: verify_string("AwsAccessKeyId", settings["AwsAccessKeyId"]),
              secret_access_key: verify_string("AwsSecretAccessKey", settings["AwsSecretAccessKey"])
            )
          when :file_system
            FileSystemRemoteConfig.new(
              remote_path: verify_string("FileSystemRemotePath", settings["FileSystemRemotePath"])
            )
          when :sftp
            SftpRemoteConfig.new(
              user: verify_string("SftpUser", settings["SftpUser"]),
              host: verify_string("SftpHost", settings["SftpHost"]),
              key_path: verify_string("SftpKeyPath", settings["SftpKeyPath"])
            )
          else
            raise ConfigError, "Remote type #{remote_type} is not supported"
          end
        )
      )
    end

    def self.create_config(data)
      LOGGER.debug(data)
      Config.new(
        settings: SettingsConfig.new(
          dry_run: verify_boolean("DryRun", to_boolean(data["DryRun"])),
          working_dir: verify_string("WorkingDir", data["WorkingDir"]),
          export_dir: verify_string("ExportDir", data["ExportDir"])
        ),
        test: TestConfig.new(
          source_dir: verify_string("TestSourceDir", data["TestSourceDir"])
        ),
        repository: RepositoryConfig.new(
          name: verify_string("Repository", data["Repository"]),
          description: verify_string("RepositoryDescription", data["RepositoryDescription"])
        ),
        archivematica: ArchivematicaConfig.new(
          base_url: verify_string("ArchivematicaBaseURL", data["ArchivematicaBaseURL"]),
          username: verify_string("ArchivematicaUsername", data["ArchivematicaUsername"]),
          api_key: verify_string("ArchivematicaAPIKey", data["ArchivematicaAPIKey"]),
          location_uuid: verify_string("LocationUUID", data["LocationUUID"])
        ),
        source_remote: create_remote_config(data["SourceRemote"]),
        target_remote: create_remote_config(data["TargetRemote"])
      )
    end

    def self.from_file(yaml_path)
      create_config(read_data_from_file(yaml_path))
    end
  end
end
