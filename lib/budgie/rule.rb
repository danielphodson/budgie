module Budgie
  CategoryRule = Struct.new(:id, :category_id, :source_col, :pattern, :created_at, keyword_init: true) do
    def matches?(value)
      value.to_s.downcase.include?(pattern.downcase)
    end
  end

  Category = Struct.new(:id, :name, :account, :output_col, :output_value, :monthly_budget,
                        :kind, :rules, :created_at, :updated_at, keyword_init: true)
end
