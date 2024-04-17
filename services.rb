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
      SemanticLogger[klass]
      S.register(:log_stream) do
        $stderr.sync = true
        $stderr
      end
      S.register(:logger) do
        if !SemanticLogger::Logger.processor.appenders.console_output?
          SemanticLogger.add_appender(io: S.log_stream, formatter: :color)
          SemanticLogger.default_level = S.config.settings.log_level
        end
      end
    end
    S.logger
  end
end

# Database Connection
S.register(:dbconnect) do
  db_config = S.db_config
  Sequel.connect(adapter: "mysql2",
    host: db_config.database.host,
    port: db_config.database.port,
    database: db_config.database.database,
    user: db_config.database.user,
    password: db_config.database.password,
    fractional_seconds: true)
end
