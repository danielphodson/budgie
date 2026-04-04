require "sqlite3"
require "fileutils"

module Budgie
  # Owns the SQLite connection lifecycle and schema migration.
  #
  # Thread safety: SQLite3::Database is not thread-safe. Each thread (or
  # request handler in a web frontend) should instantiate its own Database
  # object rather than sharing one across threads.
  class Database
    DEFAULT_PATH = File.join(Dir.home, ".budgie", "budgie.db")

    attr_reader :connection

    def initialize(db_path: DEFAULT_PATH)
      FileUtils.mkdir_p(File.dirname(db_path)) unless db_path == ":memory:"
      @connection = SQLite3::Database.new(db_path)
      @connection.results_as_hash = true
      migrate!
    end

    def close
      @connection.close
    end

    private

    def migrate!
      @connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS rules (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          name         TEXT    NOT NULL,
          account      TEXT    NOT NULL DEFAULT '',
          source_col   TEXT    NOT NULL,
          pattern      TEXT    NOT NULL,
          output_col   TEXT    NOT NULL,
          output_value TEXT    NOT NULL,
          created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
          updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
        )
      SQL
      # Add account to existing databases that predate this column
      @connection.execute("ALTER TABLE rules ADD COLUMN account TEXT NOT NULL DEFAULT ''")
    rescue SQLite3::Exception => e
      raise unless e.message.include?("duplicate column name")
    end
  end
end
