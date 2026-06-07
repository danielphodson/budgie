module Budgie
  # All SQL for category management lives here.
  # Returns Budgie::Category / Budgie::CategoryRule value objects; never exposes
  # raw hashes to callers.
  class CategoryRepository
    def initialize(database)
      @db = database.connection
    end

    # ── Categories ──────────────────────────────────────────────────────────

    def all
      categories = @db.execute("SELECT * FROM rules ORDER BY id").map { |row| row_to_category(row) }
      load_rules!(categories)
      categories
    end

    def find(id)
      row = @db.execute("SELECT * FROM rules WHERE id = ?", [id]).first
      raise CategoryNotFound, "Category #{id} not found" unless row

      category = row_to_category(row)
      load_rules!([category])
      category
    end

    # Creates a category with an optional initial list of rules.
    # Each element of +rules+ is a hash with :source_col and :pattern keys.
    def create(name:, account: "", output_col:, output_value:, monthly_budget: nil, kind: "expense", rules: [])
      rules.each { |r| validate_pattern!(r[:pattern] || r["pattern"]) }

      @db.execute(
        "INSERT INTO rules (name, account, output_col, output_value, monthly_budget, kind) VALUES (?, ?, ?, ?, ?, ?)",
        [name, account.to_s, output_col, output_value, monthly_budget, kind]
      )
      category_id = @db.last_insert_row_id

      rules.each do |r|
        insert_rule(category_id, r[:source_col] || r["source_col"], r[:pattern] || r["pattern"])
      end

      find(category_id)
    end

    # Updates scalar category attributes. Optionally replaces all rules when
    # +attrs+ includes a "rules" key (array of {source_col:, pattern:} hashes).
    def update(id, attrs)
      find(id) # raises CategoryNotFound if missing

      attrs = attrs.transform_keys(&:to_s)

      allowed = %w[name account output_col output_value monthly_budget kind]
      updates = attrs.slice(*allowed)

      unless updates.empty?
        set_clause = updates.keys.map { |k| "#{k} = ?" }.join(", ")
        set_clause += ", updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')"
        @db.execute("UPDATE rules SET #{set_clause} WHERE id = ?", [*updates.values, id])
      end

      if attrs.key?("rules")
        new_rules = Array(attrs["rules"])
        new_rules.each { |r| validate_pattern!(r["pattern"] || r[:pattern]) }
        @db.execute("DELETE FROM rule_patterns WHERE rule_id = ?", [id])
        new_rules.each do |r|
          insert_rule(id, r["source_col"] || r[:source_col], r["pattern"] || r[:pattern])
        end
      end

      find(id)
    end

    def delete(id)
      find(id) # raises CategoryNotFound if missing
      @db.execute("DELETE FROM rules WHERE id = ?", [id])
      true
    end

    # ── Rules ──────────────────────────────────────────────────────────────

    def add_rule(category_id, source_col:, pattern:)
      find(category_id) # raises CategoryNotFound if category is missing
      validate_pattern!(pattern)
      insert_rule(category_id, source_col, pattern)
      find(category_id)
    end

    def delete_rule(rule_id)
      row = @db.execute("SELECT * FROM rule_patterns WHERE id = ?", [rule_id]).first
      raise CategoryNotFound, "Rule #{rule_id} not found" unless row

      @db.execute("DELETE FROM rule_patterns WHERE id = ?", [rule_id])
      true
    end

    private

    def load_rules!(categories)
      return if categories.empty?

      placeholders = categories.map { "?" }.join(", ")
      ids = categories.map(&:id)

      rule_rows = @db.execute(
        "SELECT * FROM rule_patterns WHERE rule_id IN (#{placeholders}) ORDER BY id",
        ids
      )

      categories_by_id = categories.each_with_object({}) { |c, h| h[c.id] = c }
      rule_rows.each do |row|
        categories_by_id[row["rule_id"]]&.rules&.push(row_to_category_rule(row))
      end
    end

    def insert_rule(category_id, source_col, pattern)
      @db.execute(
        "INSERT INTO rule_patterns (rule_id, source_col, pattern) VALUES (?, ?, ?)",
        [category_id, source_col, pattern]
      )
    end

    def validate_pattern!(pattern)
      raise InvalidPattern, "Pattern cannot be empty" if pattern.to_s.strip.empty?
    end

    def row_to_category(row)
      Category.new(
        id:             row["id"],
        name:           row["name"],
        account:        row["account"].to_s,
        output_col:     row["output_col"],
        output_value:   row["output_value"],
        monthly_budget: row["monthly_budget"],
        kind:           row["kind"] || "expense",
        rules:          [],
        created_at:     row["created_at"],
        updated_at:     row["updated_at"]
      )
    end

    def row_to_category_rule(row)
      CategoryRule.new(
        id:          row["id"],
        category_id: row["rule_id"],
        source_col:  row["source_col"],
        pattern:     row["pattern"],
        created_at:  row["created_at"]
      )
    end
  end
end
