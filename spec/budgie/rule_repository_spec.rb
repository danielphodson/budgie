require "spec_helper"

RSpec.describe Budgie::RuleRepository do
  let(:db)   { Budgie::Database.new(db_path: ":memory:") }
  let(:repo) { described_class.new(db) }

  let(:valid_attrs) do
    { name: "Groceries", source_col: "description", pattern: "grocery",
      output_col: "category", output_value: "Food" }
  end

  describe "#create" do
    it "persists a rule and returns it" do
      rule = repo.create(**valid_attrs)
      expect(rule).to be_a(Budgie::Rule)
      expect(rule.id).not_to be_nil
      expect(rule.name).to eq("Groceries")
      expect(rule.pattern).to eq("grocery")
    end

    it "raises InvalidPattern for a bad regex" do
      expect {
        repo.create(**valid_attrs.merge(pattern: "[invalid"))
      }.to raise_error(Budgie::InvalidPattern)
    end
  end

  describe "#all" do
    it "returns an empty array when no rules exist" do
      expect(repo.all).to eq([])
    end

    it "returns all rules ordered by id" do
      r1 = repo.create(**valid_attrs.merge(name: "First"))
      r2 = repo.create(**valid_attrs.merge(name: "Second"))
      expect(repo.all.map(&:id)).to eq([r1.id, r2.id])
    end
  end

  describe "#find" do
    it "returns the rule by id" do
      created = repo.create(**valid_attrs)
      found   = repo.find(created.id)
      expect(found.id).to eq(created.id)
    end

    it "raises RuleNotFound for a missing id" do
      expect { repo.find(9999) }.to raise_error(Budgie::RuleNotFound)
    end
  end

  describe "#update" do
    it "updates allowed attributes" do
      rule    = repo.create(**valid_attrs)
      updated = repo.update(rule.id, { name: "Updated", output_value: "Groceries" })
      expect(updated.name).to eq("Updated")
      expect(updated.output_value).to eq("Groceries")
    end

    it "raises InvalidPattern when updating to a bad regex" do
      rule = repo.create(**valid_attrs)
      expect {
        repo.update(rule.id, { pattern: "[bad" })
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
end
