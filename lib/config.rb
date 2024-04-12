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

  APTrustAPIConfig = Struct.new(
    "APTrustAPIConfig",
    :username,
    :base_url,
    :api_key,
    keyword_init: true
  )

  APTrustConfig = Struct.new(
    "APTrustConfig",
    :api,
    :remote,
    keyword_init: true
  )

  Config = Struct.new(
    "Config",
    :settings,
    :database,
    :repository,
    :dark_blue,
    :aptrust,
    keyword_init: true
  )

  class ConfigError < StandardError
  end

  class CheckBase
    def check?(value)
      raise NotImplementedError
    end
  end

  class NotNilCheck < CheckBase
    def check?(value)
      value.nil?
    end
  end

  # class StringCheck < CheckBase
  #   def check?(value)
  #     value.is_a?(String)
  #   end
  # end

  class IntegerCheck < CheckBase
    def check?(value)
      Integer(value, exception: false).is_a?(Integer)
    end
  end

  class BooleanCheck < CheckBase
    def check?(value)
      ["true", "false"].include?(value)
    end
  end

  class LogLevelCheck < CheckBase
    LOG_LEVELS = ["info", "debug", "trace", "warn", "error", "fatal"]

    def check?(value)
      LOG_LEVELS.include?(value)
    end
  end

  class RemoteTypeCheck < CheckBase
    REMOTE_TYPES = ["file_system", "aptrust", "sftp"]

    def check?(value)
      REMOTE_TYPES.include?(value)
    end
  end

  class CheckableData
    attr_reader :data

    def initialize(data)
      @data = data
    end

    def inspect
      @data.to_s
    end

    def to_s
      @data.to_s
    end

    def raise_error(key:, value:, reason: nil)
      raise ConfigError, "Value \"#{value}\" for key \"#{key}\" is not valid. #{reason}"
    end
    private :raise_error

    def get_value(key:, checks: [], optional: false)
      value = data.fetch(key, nil)
      return value if optional && value.nil?

      NotNilCheck.new.check?(value)
      checks.each do |check|
        result = check.check?(value)
        raise_error(key: key, value: value, reason: "#{check.class} failed.") if !result
      end
      value
    end
    
    def keys
      @data.keys
    end

    def get_subset_by_key_stem(stem)
      matching_keys = data.keys.filter { |k| k.start_with?(stem) }
      filtered_data = data.slice(*matching_keys)
      new_data = {}
      filtered_data.each_pair do |key, value|
        new_key = key.sub(stem, "")
        new_data[new_key] = value
      end
      CheckableData.new(new_data)
    end
  end

  class ConfigService
    include SemanticLogger::Loggable
    attr_reader :data

    ARCHIVEMATICA_INSTANCES = ["ARCHIVEMATICA_DEV",  "ARCHIVEMATICA_LAB", "ARCHIVEMATICA_AMI", "ARCHIVEMATICA_VGA"]

    def self.create_database_config(data)
      DatabaseConfig.new(
        host: data.get_value(key: "HOST"),
        database: data.get_value(key: "DATABASE"),
        port: data.get_value(key: "PORT", checks: [IntegerCheck.new]).to_i,
        user: data.get_value(key: "USER"),
        password: data.get_value(key: "PASSWORD")
      )
    end

    def self.create_remote_config(data)
      type = data.get_value(key: "TYPE", checks: [RemoteTypeCheck.new]).to_sym
      settings = data.get_subset_by_key_stem("SETTINGS_")
      RemoteConfig.new(
        type: type,
        settings: (
          case type
          when :aptrust
            AptrustAwsRemoteConfig.new(
              region: settings.get_value(key: "BUCKET_REGION"),
              receiving_bucket: settings.get_value(key: "RECEIVING_BUCKET"),
              restore_bucket: settings.get_value(key: "RESTORE_BUCKET"),
              access_key_id: settings.get_value(key: "AWS_ACCESS_KEY_ID"),
              secret_access_key: settings.get_value(key: "AWS_SECRET_ACCESS_KEY")
            )
          when :file_system
            FileSystemRemoteConfig.new(
              remote_path: settings.get_value("FILE_SYSTEM_REMOTE_PATH")
            )
          when :sftp
            SftpRemoteConfig.new(
              user: settings.get_value(key: "USER"),
              host: settings.get_value(key: "HOST"),
              key_path: settings.get_value(key: "KEY_PATH")
            )
          else
            raise ConfigError, "Remote type #{type} is not supported."
          end
        )
      )
    end

    def self.create_archivematica_config(data)
      ArchivematicaConfig.new(
        name: data.get_value(key: "NAME"),
        repository_name: data.get_value(key: "REPOSITORY_NAME"),
        api: ArchivematicaAPIConfig.new(
          base_url: data.get_value(key: "API_BASE_URL"),
          username: data.get_value(key: "API_USERNAME"),
          api_key: data.get_value(key: "API_API_KEY"),
          location_uuid: data.get_value(key: "API_LOCATION_UUID")
        ),
        remote: create_remote_config(data.get_subset_by_key_stem("REMOTE_"))
      )
    end

    def self.create_config(data)
      data = CheckableData.new(data)
      db_data = data.get_subset_by_key_stem("DATABASE_")

      arch_configs = []
      ARCHIVEMATICA_INSTANCES.each do |instance_name|
        instance_data = data.get_subset_by_key_stem(instance_name + "_")
        arch_configs << create_archivematica_config(instance_data) if instance_data.keys.length > 0
      end

      config = Config.new(
        settings: SettingsConfig.new(
          log_level: data.get_value(key: "SETTINGS_LOG_LEVEL", checks: [LogLevelCheck.new]).to_sym,
          working_dir: data.get_value(key: "SETTINGS_WORKING_DIR"),
          export_dir: data.get_value(key: "SETTINGS_EXPORT_DIR"),
          dry_run: data.get_value(key: "SETTINGS_DRY_RUN", checks: [BooleanCheck.new]) == "true",
          object_size_limit: data.get_value(
            key: "SETTINGS_OBJECT_SIZE_LIMIT", checks: [IntegerCheck.new], optional: true
          ).to_i
        ),
        repository: RepositoryConfig.new(
          name: data.get_value(key: "REPOSITORY_NAME"),
          description: data.get_value(key: "REPOSITORY_DESCRIPTION")
        ),
        database: db_data.keys.length > 0 ? create_database_config(db_data) : nil,
        dark_blue: DarkBlueConfig.new(archivematicas: arch_configs),
        aptrust: APTrustConfig.new(
          api: APTrustAPIConfig.new(
            username: data.get_value(key: "APTRUST_API_USERNAME"),
            api_key: data.get_value(key: "APTRUST_API_API_KEY"),
            base_url: data.get_value(key: "APTRUST_API_BASE_URL")
          ),
          remote: create_remote_config(data.get_subset_by_key_stem("APTRUST_REMOTE_"))
        )
      )
    end

    def self.database_config_from_env
      db_data = CheckableData.new(ENV.to_hash).get_subset_by_key_stem("DATABASE_")
      db_data.keys.length > 0 ? create_database_config(db_data) : nil
    end

    def self.from_env
      create_config(ENV.to_hash)
    end
  end
end
