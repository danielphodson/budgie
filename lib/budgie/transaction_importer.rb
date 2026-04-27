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
            amount:        row["Amount"].to_f,
            other_party:   row["Other Party"],
            description:   row["Credit Plan Name"],
            reference:     nil,
            particulars:   row["City"],
            analysis_code: row["Country Code"]
          }
        else
          {
            account:       account,
            date:          parse_date(row["Date"]),
            amount:        row["Amount"].to_f,
            other_party:   row["Other Party"],
            description:   row["Description"],
            reference:     row["Reference"],
            particulars:   row["Particulars"],
            analysis_code: row["Analysis Code"]
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
  end
end
