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

    def initialize(rule_repository:, transaction_repository:)
      @rules = rule_repository.all
      @trepo = transaction_repository
    end

    def reprocess_all
      compiled = @rules.map { |r| [r, r.patterns] }
      transactions = @trepo.all

      transactions.each do |t|
        next if t["manual_category"]

        row = build_row(t)
        extras = {}
        compiled.each do |rule, patterns|
          next unless patterns.any? { |p| p.matches?(row[p.source_col]) }
          extras[rule.output_col] = rule.output_value
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
