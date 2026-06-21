require "json"

module Budgie
  class TransactionRepository
    def initialize(db)
      @db = db.connection
    end

    def insert_batch(transactions)
      inserted = 0
      stmt = @db.prepare(<<~SQL)
        INSERT INTO transactions (account, date, amount, other_party, description, reference, particulars, analysis_code)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      @db.transaction do
        transactions.each do |t|
          # Check if this transaction already exists using the same logic as the unique index
          params = [
            t[:account], t[:date], t[:amount],
            normalize_for_index(t[:other_party]),
            normalize_for_index(t[:description]),
            normalize_for_index(t[:reference]),
            normalize_for_index(t[:particulars]),
            normalize_for_index(t[:analysis_code])
          ]
          existing = @db.execute(<<~SQL, params)
            SELECT id FROM transactions
            WHERE account = ? AND date = ? AND amount = ?
              AND LOWER(COALESCE(other_party,'')) = ?
              AND LOWER(COALESCE(description,'')) = ?
              AND LOWER(COALESCE(reference,'')) = ?
              AND LOWER(COALESCE(particulars,'')) = ?
              AND LOWER(COALESCE(analysis_code,'')) = ?
            LIMIT 1
          SQL
          next if existing.any?
          
          stmt.execute(
            t[:account], t[:date], t[:amount],
            t[:other_party], t[:description],
            t[:reference], t[:particulars], t[:analysis_code]
          )
          inserted += @db.changes
        end
      end
      inserted
    ensure
      stmt&.close
    end

    private

    def normalize_for_index(val)
      # Mirrors the LOWER(COALESCE(...,'')) logic used in the unique index
      (val || '').downcase
    end

    def available_months
      rows = @db.execute(
        "SELECT DISTINCT substr(date, 1, 7) AS month FROM transactions ORDER BY month DESC"
      )
      rows.map { |r| r["month"] }
    end

    def for_month(year_month)
      @db.execute(
        "SELECT * FROM transactions WHERE substr(date, 1, 7) = ? ORDER BY date, id",
        [year_month]
      )
    end

    def all
      @db.execute("SELECT * FROM transactions ORDER BY date, id")
    end

    def set_processed_data(id, data_hash)
      @db.execute(
        "UPDATE transactions SET processed_data = ? WHERE id = ?",
        [data_hash.empty? ? nil : JSON.generate(data_hash), id]
      )
    end

    def set_manual_category(id, category)
      @db.execute(
        "UPDATE transactions SET manual_category = ? WHERE id = ?",
        [category, id]
      )
    end
  end
end
