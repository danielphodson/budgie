module Budgie
  # All SQL for rule management lives here.
  # Returns Budgie::Rule value objects; never exposes raw hashes to callers.
  class RuleRepository
    def initialize(database)
      @db = database.connection
    end

    def all
      @db.execute("SELECT * FROM rules ORDER BY id").map { |row| row_to_rule(row) }
    end

    def find(id)
      row = @db.execute("SELECT * FROM rules WHERE id = ?", [id]).first
      raise RuleNotFound, "Rule #{id} not found" unless row

      row_to_rule(row)
    end

    def create(name:, account: "", source_col:, pattern:, output_col:, output_value:)
      validate_pattern!(pattern)
      @db.execute(
        "INSERT INTO rules (name, account, source_col, pattern, output_col, output_value) VALUES (?, ?, ?, ?, ?, ?)",
        [name, account.to_s, source_col, pattern, output_col, output_value]
      )
      find(@db.last_insert_row_id)
    end

    def update(id, attrs)
      rule = find(id)

      allowed = %w[name account source_col pattern output_col output_value]
      updates = attrs.transform_keys(&:to_s).slice(*allowed)
      return rule if updates.empty?

      validate_pattern!(updates["pattern"]) if updates.key?("pattern")

      set_clause = updates.keys.map { |k| "#{k} = ?" }.join(", ")
      set_clause += ", updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')"

      @db.execute(
        "UPDATE rules SET #{set_clause} WHERE id = ?",
        [*updates.values, id]
      )
      find(id)
    end

    def delete(id)
      find(id) # raises RuleNotFound if missing
      @db.execute("DELETE FROM rules WHERE id = ?", [id])
      true
    end

    private

    def validate_pattern!(pattern)
      Regexp.new(pattern)
    rescue RegexpError => e
      raise InvalidPattern, "Invalid regex pattern: #{e.message}"
    end

    def row_to_rule(row)
      Rule.new(
        id:           row["id"],
        name:         row["name"],
        account:      row["account"].to_s,
        source_col:   row["source_col"],
        pattern:      row["pattern"],
        output_col:   row["output_col"],
        output_value: row["output_value"],
        created_at:   row["created_at"],
        updated_at:   row["updated_at"]
      )
    end
  end
end
