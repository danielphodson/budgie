require "yaml"

module Budgie
  class Config
    DEFAULT_FILE = File.join(Dir.home, ".budgie", "config.yml")
    DEFAULT_DB_PATH = File.join(Dir.home, "budgie.data", "budgie.db")
    DEFAULT_BACKUP_DIR = File.join(Dir.home, "budgie.data", "backups")

    attr_reader :db_path, :backup_dir, :path

    def self.load(path = nil)
      path ||= ENV["BUDGIE_CONFIG"] || DEFAULT_FILE
      config = if File.exist?(path)
        raw = YAML.safe_load(File.read(path), permitted_classes: [Symbol], aliases: true)
        unless raw.nil? || raw.is_a?(Hash)
          raise ArgumentError, "Invalid config file format: #{path}"
        end
        raw || {}
      else
        {}
      end

      new(config, path)
    end

    def initialize(config = {}, path = DEFAULT_FILE)
      @path = path
      @db_path = config["db_path"] || DEFAULT_DB_PATH
      @backup_dir = config["backup_dir"] || DEFAULT_BACKUP_DIR
    end
  end
end
