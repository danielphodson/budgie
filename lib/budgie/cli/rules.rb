require "thor"
require "tempfile"
require "yaml"

module Budgie
  module CLI
    class Rules < Thor
      desc "list", "List all rules"
      def list
        rules = repo.all
        if rules.empty?
          say "No rules defined. Use `budgie rules add` to create one."
          return
        end

        rules.each do |r|
          account_tag = r.account && !r.account.empty? ? " [#{r.account}]" : ""
          say "##{r.id}  #{r.name}#{account_tag}  →  #{r.output_col} = #{r.output_value}"
          if r.patterns.empty?
            say "      (no patterns)"
          else
            r.patterns.each do |p|
              say "      #{p.source_col} ~ #{p.pattern}"
            end
          end
        end
      end

      desc "add", "Add a new rule"
      option :name,         required: true,  aliases: "-n", desc: "Human-readable rule name"
      option :account,      required: false, aliases: "-a", desc: "Account label (written to output)"
      option :output_col,   required: true,  aliases: "-o", desc: "Column name to add to output"
      option :output_value, required: true,  aliases: "-v", desc: "Value to write in output column"
      option :source_col,   required: true,  aliases: "-c", desc: "CSV column to match against"
      option :pattern,      required: true,  aliases: "-p", desc: "Ruby regex pattern (without delimiters)"
      def add
        rule = repo.create(
          name:         options[:name],
          account:      options[:account] || "",
          output_col:   options[:output_col],
          output_value: options[:output_value],
          patterns:     [{ source_col: options[:source_col], pattern: options[:pattern] }]
        )
        say "Created rule ##{rule.id}: #{rule.name}"
      rescue InvalidPattern => e
        say "Error: #{e.message}", :red
        exit 1
      end

      desc "edit ID", "Edit a rule (and its patterns) in $EDITOR"
      def edit(id)
        rule   = repo.find(Integer(id))
        editor = ENV["EDITOR"] || "vi"

        attrs = {
          "name"         => rule.name,
          "account"      => rule.account,
          "output_col"   => rule.output_col,
          "output_value" => rule.output_value,
          "patterns"     => rule.patterns.map { |p| { "source_col" => p.source_col, "pattern" => p.pattern } }
        }

        Tempfile.create(["budgie_rule_#{id}", ".yml"]) do |f|
          f.write(attrs.to_yaml)
          f.flush

          mtime_before = File.mtime(f.path)
          exit_status  = system(editor, f.path)

          unless exit_status
            say "Editor exited with an error. No changes saved.", :red
            exit 1
          end

          if File.mtime(f.path) == mtime_before
            say "No changes detected."
            return
          end

          updated = YAML.safe_load(File.read(f.path))
          rule = repo.update(id, updated)
          say "Updated rule ##{rule.id}: #{rule.name}"
        end
      rescue RuleNotFound => e
        say "Error: #{e.message}", :red
        exit 1
      rescue InvalidPattern => e
        say "Error: #{e.message}", :red
        exit 1
      end

      desc "delete ID", "Delete a rule"
      def delete(id)
        rule = repo.find(Integer(id))
        repo.delete(Integer(id))
        say "Deleted rule ##{rule.id}: #{rule.name}"
      rescue RuleNotFound => e
        say "Error: #{e.message}", :red
        exit 1
      end

      private

      def repo
        @repo ||= begin
          db = Budgie::Database.new
          Budgie::RuleRepository.new(db)
        end
      end
    end
  end
end
