require "thor"

module Budgie
  module CLI
    class Main < Thor
      desc "process INPUT OUTPUT", "Apply rules to INPUT CSV and write augmented rows to OUTPUT CSV"
      def process(input, output)
        db   = Budgie::Database.new
        repo = Budgie::RuleRepository.new(db)
        result = Budgie::Processor.new(rule_repository: repo).process(
          input_path: input,
          output_path: output
        )
        say "Processed #{result[:rows_processed]} row(s). Added #{result[:columns_added]} column(s)."
      rescue Errno::ENOENT => e
        say "Error: #{e.message}", :red
        exit 1
      end

      desc "rules SUBCOMMAND", "Manage matching rules"
      subcommand "rules", Budgie::CLI::Rules

      desc "server SUBCOMMAND", "Start the web UI"
      subcommand "server", Budgie::CLI::Server
    end
  end
end
