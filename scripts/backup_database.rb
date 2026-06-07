#!/usr/bin/env ruby

require "fileutils"
require "sqlite3"
require "time"

# Backup the Budgie database following SQLite best practices
#
# Usage:
#   ruby scripts/backup_database.rb
#   ruby scripts/backup_database.rb /path/to/budgie.db
#   ruby scripts/backup_database.rb /path/to/budgie.db /path/to/backups

class DatabaseBackup
  DEFAULT_DB_PATH = File.join(Dir.home, "budgie.data", "budgie.db")
  DEFAULT_BACKUP_DIR = File.join(Dir.home, "budgie.data", "backups")
  RETAIN_BACKUPS = 7 # Keep last 7 backups

  def initialize(db_path = DEFAULT_DB_PATH, backup_dir = DEFAULT_BACKUP_DIR)
    @db_path = db_path
    @backup_dir = backup_dir
  end

  def run
    validate_database!
    create_backup_directory!
    checkpoint_database!
    backup_file = create_backup!
    rotate_old_backups
    puts "✓ Database backed up to #{backup_file}"
  end

  private

  def validate_database!
    unless File.exist?(@db_path)
      raise "Database not found at #{@db_path}"
    end

    # Verify it's a valid SQLite database
    db = SQLite3::Database.new @db_path
    db.execute("PRAGMA quick_check")
    db.close
  rescue => e
    raise "Database validation failed: #{e.message}"
  end

  def create_backup_directory!
    FileUtils.mkdir_p(@backup_dir) unless Dir.exist?(@backup_dir)
  end

  def checkpoint_database!
    # Ensure all pending transactions are flushed to disk.
    # RESTART mode closes and reopens the WAL, creating a clean checkpoint.
    db = SQLite3::Database.new @db_path
    db.execute("PRAGMA wal_checkpoint(RESTART)")
    db.close
  rescue => e
    warn "Warning: checkpoint failed (non-critical): #{e.message}"
  end

  def create_backup!
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    backup_file = File.join(@backup_dir, "budgie_#{timestamp}.db")

    # Copy the database file (safe after checkpoint)
    FileUtils.cp(@db_path, backup_file)

    # Verify the backup is valid
    verify_backup!(backup_file)

    backup_file
  end

  def verify_backup!(backup_file)
    db = SQLite3::Database.new backup_file
    result = db.execute("PRAGMA quick_check")
    db.close

    unless result.flatten.first == "ok"
      File.delete(backup_file)
      raise "Backup verification failed"
    end
  end

  def rotate_old_backups
    backups = Dir.glob(File.join(@backup_dir, "budgie_*.db"))
      .sort_by { |f| File.mtime(f) }
      .reverse

    if backups.size > RETAIN_BACKUPS
      old_backups = backups[RETAIN_BACKUPS..]
      old_backups.each do |backup|
        File.delete(backup)
        puts "  Deleted old backup: #{File.basename(backup)}"
      end
    end
  end
end

if __FILE__ == $0
  db_path = ARGV[0] || DatabaseBackup::DEFAULT_DB_PATH
  backup_dir = ARGV[1] || DatabaseBackup::DEFAULT_BACKUP_DIR

  begin
    DatabaseBackup.new(db_path, backup_dir).run
  rescue => e
    puts "✗ Backup failed: #{e.message}"
    exit 1
  end
end
