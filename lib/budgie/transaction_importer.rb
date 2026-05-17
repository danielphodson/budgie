require "csv"

module Budgie
  class TransactionImporter
    def initialize(transaction_repository:)
      @repo = transaction_repository
    end

    def import(path:, account:)
      table = CSV.read(path, headers: true)
      credit_card = table.headers.include?("Transaction Date")

      transactions = table.map do |row|
        if credit_card
          {
            account:       account,
            date:          parse_date(row["Transaction Date"]),
            amount:        normalize_amount(row["Amount"]),
            other_party:   normalize_str(row["Other Party"]),
            description:   normalize_str(row["Credit Plan Name"]),
            reference:     nil,
            particulars:   normalize_str(row["City"]),
            analysis_code: normalize_str(row["Country Code"])
          }
        else
          {
            account:       account,
            date:          parse_date(row["Date"]),
            amount:        normalize_amount(row["Amount"]),
            other_party:   normalize_str(row["Other Party"]),
            description:   normalize_str(row["Description"]),
            reference:     normalize_str(row["Reference"]),
            particulars:   normalize_str(row["Particulars"]),
            analysis_code: normalize_str(row["Analysis Code"])
          }
        end
      end

      @repo.insert_batch(transactions)
    end

    private

    def parse_date(str)
      return nil unless str
      d, m, y = str.strip.split("/")
      "#{y}-#{m.rjust(2, '0')}-#{d.rjust(2, '0')}"
    end

    def normalize_str(val)
      return nil unless val
      s = val.to_s.strip
      s = s.gsub(/\s+/, ' ')
      s = s.upcase
      s.empty? ? nil : s
    end

    def normalize_amount(val)
      return 0.0 unless val
      # Round to 2 decimal places to avoid float precision mismatches
      val.to_f.round(2)
    end
  end
end
