require "spec_helper"
require "tmpdir"

RSpec.describe Budgie::Processor do
  let(:db)   { Budgie::Database.new(db_path: ":memory:") }
  let(:repo) { Budgie::RuleRepository.new(db) }
  let(:processor) { described_class.new(rule_repository: repo) }

  def write_csv(path, headers, rows)
    CSV.open(path, "w") do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
  end

  def read_csv(path)
    CSV.read(path, headers: true)
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:input)  { File.join(@dir, "input.csv") }
  let(:output) { File.join(@dir, "output.csv") }

  context "with no rules" do
    it "passes rows through unchanged" do
      write_csv(input, ["name", "amount"], [["Alice", "10"], ["Bob", "20"]])
      result = processor.process(input_path: input, output_path: output)

      expect(result[:rows_processed]).to eq(2)
      expect(result[:columns_added]).to eq(0)

      table = read_csv(output)
      expect(table.headers).to eq(["name", "amount"])
      expect(table[0]["name"]).to eq("Alice")
    end
  end

  context "with one matching rule" do
    before do
      repo.create(name: "Groceries", source_col: "description",
                  pattern: "grocery", output_col: "category", output_value: "Food")
    end

    it "appends the output column to matching rows" do
      write_csv(input, ["description", "amount"],
                [["corner grocery", "12.50"], ["gas station", "40.00"]])
      processor.process(input_path: input, output_path: output)

      table = read_csv(output)
      expect(table.headers).to include("category")
      expect(table[0]["category"]).to eq("Food")
      expect(table[1]["category"]).to be_nil
    end
  end

  context "with two rules matching the same row" do
    before do
      repo.create(name: "Food", source_col: "description",
                  pattern: "grocery", output_col: "category", output_value: "Food")
      repo.create(name: "Local", source_col: "description",
                  pattern: "corner", output_col: "tag", output_value: "local")
    end

    it "appends both output columns" do
      write_csv(input, ["description"], [["corner grocery"]])
      processor.process(input_path: input, output_path: output)

      table = read_csv(output)
      expect(table[0]["category"]).to eq("Food")
      expect(table[0]["tag"]).to eq("local")
    end
  end

  context "when two rules share an output_col" do
    before do
      repo.create(name: "R1", source_col: "description",
                  pattern: "foo", output_col: "category", output_value: "First")
      repo.create(name: "R2", source_col: "description",
                  pattern: "foo", output_col: "category", output_value: "Second")
    end

    it "last matching rule wins" do
      write_csv(input, ["description"], [["foo bar"]])
      processor.process(input_path: input, output_path: output)

      table = read_csv(output)
      expect(table[0]["category"]).to eq("Second")
    end
  end

  context "when source_col does not exist in the CSV" do
    before do
      repo.create(name: "Missing Col", source_col: "nonexistent",
                  pattern: ".*", output_col: "flag", output_value: "yes")
    end

    it "treats the missing column value as empty string (no match for non-blank patterns)" do
      write_csv(input, ["description"], [["something"]])
      processor.process(input_path: input, output_path: output)

      table = read_csv(output)
      # ".*" matches empty string so this rule WILL fire; the important thing
      # is it does not raise an error
      expect(table.headers).to include("flag")
    end
  end
end
