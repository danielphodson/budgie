require "sqlite3"
require "csv"
require "fileutils"
require "yaml"
require "tempfile"

require_relative "budgie/version"
require_relative "budgie/database"
require_relative "budgie/rule"
require_relative "budgie/rule_repository"
require_relative "budgie/processor"
require_relative "budgie/transaction_repository"
require_relative "budgie/transaction_importer"
require_relative "budgie/transaction_processor"
require_relative "budgie/server"
require_relative "budgie/cli/rules"
require_relative "budgie/cli/server"
require_relative "budgie/cli/main"

module Budgie
  class Error < StandardError; end
  class CategoryNotFound < Error; end
  class InvalidPattern < Error; end
end
