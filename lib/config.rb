require "yaml"

require "semantic_logger"

module Config
  SettingsConfig = Struct.new(
    "SettingsConfig",
    :log_level,
    :working_dir,
    :export_dir,
    :dry_run,
    :object_size_limit,
    keyword_init: true
  )

  DatabaseConfig = Struct.new(
    "DatabaseConfig",
    :host,
    :database,
    :user,
    :password,
    :port,
    keyword_init: true
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

  ArchivematicaAPIConfig = Struct.new(
    "ArchivematicaAPIConfig",
    :username,
    :base_url,
    :api_key,
    :location_uuid,
    keyword_init: true
  )

  ArchivematicaConfig = Struct.new(
    "ArchivematicaConfig",
    :name,
    :repository_name,
    :api,
    :remote,
    keyword_init: true
  )

  DarkBlueConfig = Struct.new(
    "DarkBlueConfig",
    :archivematicas,
    keyword_init: true
  )

  Config = Struct.new(
    "Config",
    :settings,
    :database,
    :repository,
    :target_remote,
    :dark_blue,
    keyword_init: true
  )

  class ConfigError < StandardError
  end

  class ConfigService
    include SemanticLogger::Loggable

    def self.raise_error(key, value)
      raise ConfigError, "Value for \"#{key}\" is not valid: #{value}"
    end

    def self.verify_string(key, value)
      if !value.is_a?(String)
        raise_error(key, value)
      end
      value
    end

    def self.verify_int(key, value)
      if !value.is_a?(Integer)
        raise_error(key, value)
      end
      value
    end

    def self.verify_boolean(key, value)
      if ![true, false].include?(value)
        raise_error(key, value)
      end
      value
    end

    def self.read_data_from_file(yaml_path)
      logger.debug("yaml_path=#{yaml_path}")
      YAML.safe_load_file(yaml_path)
    end

    # TO DO
    # Support config from environment?

    def self.create_remote_config(data)
      type = verify_string("Type", data["Type"]).to_sym
      settings = data["Settings"]
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
              user: verify_string("User", settings["User"]),
              host: verify_string("Host", settings["Host"]),
              key_path: verify_string("KeyPath", settings["KeyPath"])
            )
          else
            raise ConfigError, "Remote type #{type} is not supported"
          end
        )
      )
    end

    def self.create_config(data)
      logger.debug(data)
      db_data = data.fetch("Database", nil)
      Config.new(
        settings: SettingsConfig.new(
          log_level: verify_string("LogLevel", data["LogLevel"]).to_sym,
          working_dir: verify_string("WorkingDir", data["WorkingDir"]),
          export_dir: verify_string("ExportDir", data["ExportDir"]),
          dry_run: verify_boolean("DryRun", data["DryRun"]),
          object_size_limit: data["ObjectSizeLimit"] && verify_int("ObjectSizeLimit", data["ObjectSizeLimit"])
        ),
        repository: RepositoryConfig.new(
          name: verify_string("Repository", data["Repository"]),
          description: verify_string("RepositoryDescription", data["RepositoryDescription"])
        ),
        database: db_data && DatabaseConfig.new(
          host: verify_string("Host", db_data["Host"]),
          database: verify_string("Database", db_data["Database"]),
          port: verify_int("Port", db_data["Port"]),
          user: verify_string("User", db_data["User"]),
          password: verify_string("Password", db_data["Password"])
        ),
        dark_blue: DarkBlueConfig.new(
          archivematicas: (
            data["DarkBlue"]["ArchivematicaInstances"].map do |arch_data|
              api_data = arch_data["API"]
              remote_data = arch_data["Remote"]
              ArchivematicaConfig.new(
                name: verify_string("Name", arch_data["Name"]),
                repository_name: verify_string("RepositoryName", arch_data["RepositoryName"]),
                api: ArchivematicaAPIConfig.new(
                  base_url: verify_string("BaseURL", api_data["BaseURL"]),
                  username: verify_string("Username", api_data["Username"]),
                  api_key: verify_string("APIKey", api_data["APIKey"]),
                  location_uuid: verify_string("LocationUUID", api_data["LocationUUID"])
                ),
                remote: create_remote_config(remote_data)
              )
            end
          )
        ),
        target_remote: create_remote_config(data["TargetRemote"])
      )
    end

    def self.from_file(yaml_path)
      create_config(read_data_from_file(yaml_path))
    end
  end
end
