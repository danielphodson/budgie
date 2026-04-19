require "spec_helper"

RSpec.describe Budgie::RuleRepository do
  let(:db)   { Budgie::Database.new(db_path: ":memory:") }
  let(:repo) { described_class.new(db) }

  let(:valid_attrs) do
    { name: "Groceries", output_col: "category", output_value: "Food",
      patterns: [{ source_col: "description", pattern: "grocery" }] }
  end

  describe "#create" do
    it "persists a rule and returns it with patterns" do
      rule = repo.create(**valid_attrs)
      expect(rule).to be_a(Budgie::Rule)
      expect(rule.id).not_to be_nil
      expect(rule.name).to eq("Groceries")
      expect(rule.patterns.length).to eq(1)
      expect(rule.patterns.first.pattern).to eq("grocery")
    end

    it "creates a rule with no initial patterns" do
      rule = repo.create(name: "Empty", output_col: "category", output_value: "Other")
      expect(rule.patterns).to be_empty
    end

    it "raises InvalidPattern for an empty pattern" do
      expect {
        repo.create(**valid_attrs.merge(patterns: [{ source_col: "description", pattern: "" }]))
      }.to raise_error(Budgie::InvalidPattern)
    end
  end

  describe "#all" do
    it "returns an empty array when no rules exist" do
      expect(repo.all).to eq([])
    end

    it "returns all rules ordered by id, with patterns loaded" do
      r1 = repo.create(**valid_attrs.merge(name: "First"))
      r2 = repo.create(**valid_attrs.merge(name: "Second"))
      all = repo.all
      expect(all.map(&:id)).to eq([r1.id, r2.id])
      expect(all.first.patterns.length).to eq(1)
    end
  end

  describe "#find" do
    it "returns the rule by id with patterns" do
      created = repo.create(**valid_attrs)
      found   = repo.find(created.id)
      expect(found.id).to eq(created.id)
      expect(found.patterns.length).to eq(1)
    end

    it "raises RuleNotFound for a missing id" do
      expect { repo.find(9999) }.to raise_error(Budgie::RuleNotFound)
    end
  end

  describe "#update" do
    it "updates scalar attributes" do
      rule    = repo.create(**valid_attrs)
      updated = repo.update(rule.id, { name: "Updated", output_value: "Groceries" })
      expect(updated.name).to eq("Updated")
      expect(updated.output_value).to eq("Groceries")
    end

    it "replaces patterns when 'patterns' key is provided" do
      rule = repo.create(**valid_attrs)
      updated = repo.update(rule.id, {
        "patterns" => [
          { "source_col" => "description", "pattern" => "supermarket" },
          { "source_col" => "description", "pattern" => "grocery" }
        ]
      })
      expect(updated.patterns.length).to eq(2)
      expect(updated.patterns.map(&:pattern)).to contain_exactly("supermarket", "grocery")
    end

    it "raises InvalidPattern when updating with an empty pattern" do
      rule = repo.create(**valid_attrs)
      expect {
        repo.update(rule.id, { "patterns" => [{ "source_col" => "description", "pattern" => "" }] })
      }.to raise_error(Budgie::InvalidPattern)
    end

    it "raises RuleNotFound for a missing id" do
      expect { repo.update(9999, { name: "X" }) }.to raise_error(Budgie::RuleNotFound)
    end
  end

  describe "#delete" do
    it "removes the rule and returns true" do
      rule = repo.create(**valid_attrs)
      expect(repo.delete(rule.id)).to be(true)
      expect { repo.find(rule.id) }.to raise_error(Budgie::RuleNotFound)
    end

    it "raises RuleNotFound for a missing id" do
      expect { repo.delete(9999) }.to raise_error(Budgie::RuleNotFound)
    end
  end

  describe "#add_pattern" do
    it "adds a pattern to an existing rule" do
      rule    = repo.create(**valid_attrs)
      updated = repo.add_pattern(rule.id, source_col: "description", pattern: "supermarket")
      expect(updated.patterns.length).to eq(2)
    end

    it "raises InvalidPattern for an empty pattern" do
      rule = repo.create(**valid_attrs)
      expect {
        repo.add_pattern(rule.id, source_col: "description", pattern: "")
      }.to raise_error(Budgie::InvalidPattern)
    end

    it "raises RuleNotFound for a missing rule id" do
      expect {
        repo.add_pattern(9999, source_col: "description", pattern: "grocery")
      }.to raise_error(Budgie::RuleNotFound)
    end
  end

  describe "#delete_pattern" do
    it "removes a pattern" do
      rule       = repo.create(**valid_attrs)
      pattern_id = rule.patterns.first.id
      expect(repo.delete_pattern(pattern_id)).to be(true)
      expect(repo.find(rule.id).patterns).to be_empty
    end

    it "raises RuleNotFound for a missing pattern id" do
      expect { repo.delete_pattern(9999) }.to raise_error(Budgie::RuleNotFound)
    end
  end
end
