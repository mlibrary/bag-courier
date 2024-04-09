require "canister"
require "semantic_logger"
require "sequel"
require_relative "lib/config"

Services = Canister.new

S = Services

# Config
S.register(:config) do
  Config::ConfigService.from_file(File.join(".", "config", "config.yml"))
end

def config
  S.config
end

# Logger
module DarkBlueLogger
  def self.included(klass)
    klass.class_exec do
      include SemanticLogger
      include SemanticLogger::Loggable
      SemanticLogger[klass]
      S.register(:log_stream) do
        $stdout.sync = true
        $stdout
      end
      S.register(:logger) do
        if !SemanticLogger::Logger.processor.appenders.console_output?
          SemanticLogger.add_appender(io: S.log_stream, formatter: :color)
          SemanticLogger.default_level = config.settings.log_level
        end
      end
    end
    S.logger
  end
end

# Database Connection
S.register(:dbconnect) do
  Sequel.connect(adapter: "mysql2",
    host: config.database.host,
    port: config.database.port,
    database: config.database.database,
    user: config.database.user,
    password: config.database.password,
    fractional_seconds: true)
end

def dbconnect
  S.dbconnect
end
