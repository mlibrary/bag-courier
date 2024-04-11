require "minitest"
require "sequel/core"

require_relative "../db/database_error"
require_relative "../lib/config"

Sequel.extension :migration

db_config = Config::ConfigService.database_config_from_env

if !db_config
  message = "A database connection is not configured. This is required for some tests."
  raise DatabaseError, message
end

DB = Sequel.connect(
  adapter: "mysql2",
  host: db_config.host,
  port: db_config.port,
  database: "test_database",
  user: db_config.user,
  password: db_config.password,
  fractional_seconds: true
)

Sequel::Migrator.run(DB, "db/migrations")

# https://sequel.jeremyevans.net/rdoc/files/doc/testing_rdoc.html

class SequelTestCase < Minitest::Test
  def run(*args, &block)
    DB.transaction(rollback: :always, auto_savepoint: true) { super }
  end
end
