module Budgie
  # All SQL for rule management lives here.
  # Returns Budgie::Rule / Budgie::RulePattern value objects; never exposes
  # raw hashes to callers.
  class RuleRepository
    def initialize(database)
      @db = database.connection
    end

    # ── Rules ──────────────────────────────────────────────────────────────

    def all
      rules = @db.execute("SELECT * FROM rules ORDER BY id").map { |row| row_to_rule(row) }
      load_patterns!(rules)
      rules
    end

    def find(id)
      row = @db.execute("SELECT * FROM rules WHERE id = ?", [id]).first
      raise RuleNotFound, "Rule #{id} not found" unless row

      rule = row_to_rule(row)
      load_patterns!([rule])
      rule
    end

    # Creates a rule with an optional initial list of patterns.
    # Each element of +patterns+ is a hash with :source_col and :pattern keys.
    def create(name:, account: "", output_col:, output_value:, monthly_budget: nil, kind: "expense", patterns: [])
      patterns.each { |p| validate_pattern!(p[:pattern] || p["pattern"]) }

      @db.execute(
        "INSERT INTO rules (name, account, output_col, output_value, monthly_budget, kind) VALUES (?, ?, ?, ?, ?, ?)",
        [name, account.to_s, output_col, output_value, monthly_budget, kind]
      )
      rule_id = @db.last_insert_row_id

      patterns.each do |p|
        insert_pattern(rule_id, p[:source_col] || p["source_col"], p[:pattern] || p["pattern"])
      end

      find(rule_id)
    end

    # Updates scalar rule attributes. Optionally replaces all patterns when
    # +attrs+ includes a "patterns" key (array of {source_col:, pattern:} hashes).
    def update(id, attrs)
      find(id) # raises RuleNotFound if missing

      attrs = attrs.transform_keys(&:to_s)

      allowed = %w[name account output_col output_value monthly_budget kind]
      updates = attrs.slice(*allowed)

      unless updates.empty?
        set_clause = updates.keys.map { |k| "#{k} = ?" }.join(", ")
        set_clause += ", updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')"
        @db.execute("UPDATE rules SET #{set_clause} WHERE id = ?", [*updates.values, id])
      end

      if attrs.key?("patterns")
        new_patterns = Array(attrs["patterns"])
        new_patterns.each { |p| validate_pattern!(p["pattern"] || p[:pattern]) }
        @db.execute("DELETE FROM rule_patterns WHERE rule_id = ?", [id])
        new_patterns.each do |p|
          insert_pattern(id, p["source_col"] || p[:source_col], p["pattern"] || p[:pattern])
        end
      end

      find(id)
    end

    def delete(id)
      find(id) # raises RuleNotFound if missing
      @db.execute("DELETE FROM rules WHERE id = ?", [id])
      true
    end

    # ── Patterns ───────────────────────────────────────────────────────────

    def add_pattern(rule_id, source_col:, pattern:)
      find(rule_id) # raises RuleNotFound if rule is missing
      validate_pattern!(pattern)
      insert_pattern(rule_id, source_col, pattern)
      find(rule_id)
    end

    def delete_pattern(pattern_id)
      row = @db.execute("SELECT * FROM rule_patterns WHERE id = ?", [pattern_id]).first
      raise RuleNotFound, "Pattern #{pattern_id} not found" unless row

      @db.execute("DELETE FROM rule_patterns WHERE id = ?", [pattern_id])
      true
    end

    private

    def load_patterns!(rules)
      return if rules.empty?

      placeholders = rules.map { "?" }.join(", ")
      ids = rules.map(&:id)

      pattern_rows = @db.execute(
        "SELECT * FROM rule_patterns WHERE rule_id IN (#{placeholders}) ORDER BY id",
        ids
      )

      rules_by_id = rules.each_with_object({}) { |r, h| h[r.id] = r }
      pattern_rows.each do |row|
        rules_by_id[row["rule_id"]]&.patterns&.push(row_to_pattern(row))
      end
    end

    def insert_pattern(rule_id, source_col, pattern)
      @db.execute(
        "INSERT INTO rule_patterns (rule_id, source_col, pattern) VALUES (?, ?, ?)",
        [rule_id, source_col, pattern]
      )
    end

    def validate_pattern!(pattern)
      raise InvalidPattern, "Pattern cannot be empty" if pattern.to_s.strip.empty?
    end

    def row_to_rule(row)
      Rule.new(
        id:             row["id"],
        name:           row["name"],
        account:        row["account"].to_s,
        output_col:     row["output_col"],
        output_value:   row["output_value"],
        monthly_budget: row["monthly_budget"],
        kind:           row["kind"] || "expense",
        patterns:       [],
        created_at:     row["created_at"],
        updated_at:     row["updated_at"]
      )
    end

    def row_to_pattern(row)
      RulePattern.new(
        id:         row["id"],
        rule_id:    row["rule_id"],
        source_col: row["source_col"],
        pattern:    row["pattern"],
        created_at: row["created_at"]
      )
    end
  end
end
