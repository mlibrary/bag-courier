$LOAD_PATH.unshift(File.dirname(__FILE__))
require "minitest/test_task"

Minitest::TestTask.create

task default: :test

namespace :db do
  desc "Run migrations"
  task :migrate, [:version] do |t, args|
    require "sequel/core"
    require_relative "db/database_error"
    require "services"

    Sequel.extension :migration

    if !db_config
      raise DatabaseError, "Migration failed. A database connection is not configured."
    end

    version = args[:version].to_i if args[:version]
    Sequel::Migrator.run(dbconnect, "db/migrations", target: version)
  end
end
