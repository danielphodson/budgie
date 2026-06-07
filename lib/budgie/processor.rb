require "csv"

module Budgie
  # Core CSV transform engine. Takes a CategoryRepository so it is fully
  # testable with a stub. No file I/O in the constructor.
  class Processor
    def initialize(category_repository:)
      @repo = category_repository
    end

    # Reads input_path, applies rules, writes augmented rows to output_path.
    # Returns a result hash: { rows_processed:, columns_added: }
    def process(input_path:, output_path:)
      categories = @repo.all

      compiled_categories = categories.map { |category| [category, category.rules] }

      table = CSV.read(input_path, headers: true)
      original_headers = table.headers

      augmented = []
      extra_col_set = []

      table.each do |row|
        extras = {}
        compiled_categories.each do |category, compiled_rules|
          # Category rule fires if any of its rule patterns matches the corresponding column.
          next unless compiled_rules.any? { |pattern| pattern.matches?(row[pattern.source_col]) }

          # Last matching category wins when multiple categories share an output_col.
          extras["account"]         = category.account if category.account && !category.account.empty?
          extras[category.output_col] = category.output_value

          extra_col_set << category.output_col unless extra_col_set.include?(category.output_col)
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
