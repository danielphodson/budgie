require "csv"

module Budgie
  # Core CSV transform engine. Takes a RuleRepository so it is fully
  # testable with a stub. No file I/O in the constructor.
  class Processor
    def initialize(rule_repository:)
      @repo = rule_repository
    end

    # Reads input_path, applies rules, writes augmented rows to output_path.
    # Returns a result hash: { rows_processed:, columns_added: }
    def process(input_path:, output_path:)
      rules = @repo.all
      compiled = rules.map { |r| [r, r.compiled_pattern] }

      table = CSV.read(input_path, headers: true)
      original_headers = table.headers

      augmented = []
      extra_col_set = []

      table.each do |row|
        extras = {}
        compiled.each do |rule, pattern|
          next unless pattern.match?(row[rule.source_col].to_s)

          # Last matching rule wins when multiple rules share an output_col.
          extras["account"]      = rule.account if rule.account && !rule.account.empty?
          extras[rule.output_col] = rule.output_value

          extra_col_set << rule.output_col unless extra_col_set.include?(rule.output_col)
        end
        augmented << row.to_h.merge(extras)
      end

      # account always comes first if any rule set it, then remaining cols sorted
      has_account = augmented.any? { |r| r.key?("account") }
      extra_cols  = (has_account ? ["account"] : []) + extra_col_set.sort
      headers = original_headers + extra_cols

      CSV.open(output_path, "w") do |csv|
        csv << headers
        augmented.each do |row|
          csv << headers.map { |h| row[h] }
        end
      end

      { rows_processed: augmented.size, columns_added: extra_cols.size }
    end
  end
end
