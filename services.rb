require "canister"
require "semantic_logger"
require "sequel"

require_relative "lib/config"

Services = Canister.new

S = Services

# Config
S.register(:config) do
  Config::ConfigService.from_env
end

S.register(:db_config) do
  Config::ConfigService.database_config_from_env
end

# Logger
module DarkBlueLogger
  def self.included(klass)
    klass.class_exec do
      include SemanticLogger
      include SemanticLogger::Loggable
      logger = SemanticLogger[klass]
      if !SemanticLogger::Logger.processor.appenders.console_output?
        SemanticLogger.add_appender(io: $stderr, formatter: :color)
        SemanticLogger.default_level = Config::ConfigService.log_level_from_env
      end
      logger
    end
  end
end

# Database Connection
S.register(:dbconnect) do
  db_config = S.db_config
  Sequel.connect(adapter: "mysql2",
    host: db_config.host,
    port: db_config.port,
    database: db_config.database,
    user: db_config.user,
    password: db_config.password,
    fractional_seconds: true)
end

S.register(:status_event_repo) do
  db = S.config.database && S.dbconnect
  StatusEventRepository::StatusEventRepositoryFactory.for(use_db: db)
end
