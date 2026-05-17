require "sqlite3"
require "fileutils"

module Budgie
  # Owns the SQLite connection lifecycle and schema migration.
  #
  # Thread safety: SQLite3::Database is not thread-safe. Each thread (or
  # request handler in a web frontend) should instantiate its own Database
  # object rather than sharing one across threads.
  class Database
    DEFAULT_PATH = File.join(Dir.home,"budgie.data", "budgie.db")

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
      add_processed_data_column!
      add_monthly_budget_column!
      add_manual_category_column!
      add_kind_column!
      add_transaction_unique_index!
    end

    def create_tables!
      @connection.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS transactions (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          account       TEXT    NOT NULL,
          date          TEXT    NOT NULL,
          amount        REAL    NOT NULL,
          other_party   TEXT,
          description   TEXT,
          reference     TEXT,
          particulars   TEXT,
          analysis_code TEXT,
          uploaded_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
        )
      SQL

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

    def add_processed_data_column!
      @connection.execute("ALTER TABLE transactions ADD COLUMN processed_data TEXT")
    rescue SQLite3::Exception => e
      raise unless e.message.include?("duplicate column name") ||
                   e.message.include?("no such table")
    end

    def add_monthly_budget_column!
      @connection.execute("ALTER TABLE rules ADD COLUMN monthly_budget REAL")
    rescue SQLite3::Exception => e
      raise unless e.message.include?("duplicate column name")
    end

    def add_manual_category_column!
      @connection.execute("ALTER TABLE transactions ADD COLUMN manual_category TEXT")
    rescue SQLite3::Exception => e
      raise unless e.message.include?("duplicate column name") ||
                   e.message.include?("no such table")
    end

    def add_kind_column!
      @connection.execute("ALTER TABLE rules ADD COLUMN kind TEXT NOT NULL DEFAULT 'expense'")
    rescue SQLite3::Exception => e
      raise unless e.message.include?("duplicate column name")
    end

    def add_transaction_unique_index!
      return if @connection.execute("PRAGMA index_info(idx_transactions_unique)").any?

      # Remove duplicates keeping the row that has a manual_category set, else the earliest row.
      @connection.execute(<<~SQL)
        DELETE FROM transactions WHERE id NOT IN (
          SELECT COALESCE(MIN(CASE WHEN manual_category IS NOT NULL THEN id END), MIN(id))
          FROM transactions
          GROUP BY account, date, amount,
                   LOWER(COALESCE(other_party,'')),   LOWER(COALESCE(description,'')),
                   LOWER(COALESCE(reference,'')),     LOWER(COALESCE(particulars,'')),
                   LOWER(COALESCE(analysis_code,''))
        )
      SQL

      @connection.execute(<<~SQL)
        CREATE UNIQUE INDEX idx_transactions_unique ON transactions (
          account, date, amount,
          LOWER(COALESCE(other_party,'')),   LOWER(COALESCE(description,'')),
          LOWER(COALESCE(reference,'')),     LOWER(COALESCE(particulars,'')),
          LOWER(COALESCE(analysis_code,''))
        )
      SQL
    end
  end
end
