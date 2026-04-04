module Budgie
  Rule = Struct.new(:id, :name, :account, :source_col, :pattern,
                    :output_col, :output_value,
                    :created_at, :updated_at, keyword_init: true) do
    def compiled_pattern
      Regexp.new(pattern)
    end
  end
end
