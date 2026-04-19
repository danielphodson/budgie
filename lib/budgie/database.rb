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
      @connection.execute("PRAGMA foreign_keys = ON")
      migrate!
    end

    def close
      @connection.close
    end

    private

    def migrate!
      create_tables!
      migrate_v1_to_v2! if v1_schema?
      add_account_column!
    end

    def create_tables!
      @connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS rules (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          name         TEXT    NOT NULL,
          account      TEXT    NOT NULL DEFAULT '',
          output_col   TEXT    NOT NULL,
          output_value TEXT    NOT NULL,
          created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
          updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
        )
      SQL

      @connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS rule_patterns (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          rule_id    INTEGER NOT NULL REFERENCES rules(id) ON DELETE CASCADE,
          source_col TEXT    NOT NULL,
          pattern    TEXT    NOT NULL,
          created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
        )
      SQL
    end

    # Returns true if the rules table still has the old source_col / pattern columns.
    def v1_schema?
      cols = @connection.execute("PRAGMA table_info(rules)").map { |r| r["name"] }
      cols.include?("source_col")
    end

    # Moves source_col + pattern out of rules into rule_patterns, then
    # recreates the rules table without those columns.
    def migrate_v1_to_v2!
      old_cols = @connection.execute("PRAGMA table_info(rules)").map { |r| r["name"] }
      has_account = old_cols.include?("account")

      @connection.transaction do
        # Seed rule_patterns from existing rules
        @connection.execute("SELECT * FROM rules").each do |row|
          @connection.execute(
            "INSERT INTO rule_patterns (rule_id, source_col, pattern) VALUES (?, ?, ?)",
            [row["id"], row["source_col"], row["pattern"]]
          )
        end

        @connection.execute(<<~SQL)
          CREATE TABLE rules_new (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            name         TEXT    NOT NULL,
            account      TEXT    NOT NULL DEFAULT '',
            output_col   TEXT    NOT NULL,
            output_value TEXT    NOT NULL,
            created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
            updated_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
          )
        SQL

        select_cols = has_account \
          ? "id, name, account, output_col, output_value, created_at, updated_at"
          : "id, name,          output_col, output_value, created_at, updated_at"

        @connection.execute(
          "INSERT INTO rules_new SELECT #{select_cols} FROM rules"
        )

        @connection.execute("DROP TABLE rules")
        @connection.execute("ALTER TABLE rules_new RENAME TO rules")
      end
    end

    def add_account_column!
      @connection.execute("ALTER TABLE rules ADD COLUMN account TEXT NOT NULL DEFAULT ''")
    rescue SQLite3::Exception => e
      raise unless e.message.include?("duplicate column name")
    end
  end
end
