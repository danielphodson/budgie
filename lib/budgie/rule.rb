module Budgie
  RulePattern = Struct.new(:id, :rule_id, :source_col, :pattern, :created_at, keyword_init: true) do
    def matches?(value)
      value.to_s.downcase.include?(pattern.downcase)
    end
  end

  Rule = Struct.new(:id, :name, :account, :output_col, :output_value, :patterns,
                    :created_at, :updated_at, keyword_init: true)
end
