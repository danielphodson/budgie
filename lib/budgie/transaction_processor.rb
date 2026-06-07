module Budgie
  class TransactionProcessor
    # Maps DB column names to the CSV column names that rules are defined against.
    COLUMN_MAP = {
      "other_party"   => "Other Party",
      "description"   => "Description",
      "reference"     => "Reference",
      "particulars"   => "Particulars",
      "analysis_code" => "Analysis Code",
      "date"          => "Date",
      "amount"        => "Amount",
      "account"       => "account",
    }.freeze

    def initialize(category_repository:, transaction_repository:)
      @categories = category_repository.all
      @trepo = transaction_repository
    end

    def reprocess_all
      compiled = @categories.map { |category| [category, category.rules] }
      transactions = @trepo.all

      transactions.each do |t|
        next if t["manual_category"]

        row = build_row(t)
        extras = {}
        compiled.each do |category, rules|
          next unless rules.any? { |rule| rule.matches?(row[rule.source_col]) }
          extras[category.output_col] = category.output_value
        end
        @trepo.set_processed_data(t["id"], extras)
      end

      transactions.size
    end

    private

    def build_row(t)
      COLUMN_MAP.each_with_object({}) do |(db_col, csv_col), h|
        h[csv_col] = t[db_col].to_s
      end
    end
  end
end
