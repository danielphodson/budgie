#!/usr/bin/env ruby
# Usage: bundle exec ruby scripts/seed_rules.rb path/to/transactions.csv
#
# Reads a categorised CSV and creates one Budgie rule per category.
# Each unique "Other Party" value in that category becomes a pattern.
# Skips rules and patterns that already exist.

require_relative "../lib/budgie"

csv_path = ARGV[0]
abort "Usage: #{$PROGRAM_NAME} <csv_file>" unless csv_path
abort "File not found: #{csv_path}" unless File.exist?(csv_path)

SOURCE_COL = "Other Party"
OUTPUT_COL = "Category"

# Parse CSV, stripping a UTF-8 BOM if present.
raw = File.read(csv_path, encoding: "bom|utf-8")
table = CSV.parse(raw, headers: true)

# Find the category column case-insensitively.
category_col = table.headers.find { |h| h&.downcase == "category" }
abort "Could not find a 'Category' or 'CATEGORY' column in #{csv_path}" unless category_col

source_col = table.headers.find { |h| h == SOURCE_COL }
abort "Could not find an '#{SOURCE_COL}' column in #{csv_path}" unless source_col

# Group unique Other Party values by category, stripping whitespace.
by_category = Hash.new { |h, k| h[k] = [] }
table.each do |row|
  category    = row[category_col]&.strip
  other_party = row[source_col]&.strip
  next if category.nil? || category.empty?
  next if other_party.nil? || other_party.empty?
  by_category[category] << other_party unless by_category[category].include?(other_party)
end

if by_category.empty?
  abort "No categorised rows found. Are the column headers '#{SOURCE_COL}' and '#{category_col}' correct?"
end

db   = Budgie::Database.new
repo = Budgie::RuleRepository.new(db)

# Build a lookup of existing rules by output_value so we can skip duplicates.
existing = repo.all.each_with_object({}) { |r, h| h[r.output_value] = r }

created_rules    = 0
skipped_rules    = 0
created_patterns = 0
skipped_patterns = 0

by_category.each do |category, other_parties|
  rule = existing[category]

  if rule.nil?
    # Create the rule with all patterns at once.
    patterns = other_parties.map do |op|
      { source_col: SOURCE_COL, pattern: op }
    end

    begin
      rule = repo.create(
        name:         category,
        output_col:   OUTPUT_COL,
        output_value: category,
        patterns:     patterns
      )
      puts "Created rule '#{category}' with #{patterns.size} pattern(s)"
      created_rules    += 1
      created_patterns += patterns.size
    rescue Budgie::InvalidPattern => e
      puts "ERROR creating rule '#{category}': #{e.message}"
    end
  else
    skipped_rules += 1
    # Rule exists — add any missing patterns.
    existing_patterns = rule.patterns.map(&:pattern)

    other_parties.each do |op|
      pattern = op
      if existing_patterns.include?(pattern)
        skipped_patterns += 1
        next
      end

      begin
        repo.add_pattern(rule.id, source_col: SOURCE_COL, pattern: pattern)
        puts "  Added pattern to '#{category}': #{op}"
        created_patterns += 1
      rescue Budgie::InvalidPattern => e
        puts "  ERROR adding pattern to '#{category}': #{e.message}"
      end
    end

    puts "Rule '#{category}' already exists — #{created_patterns > 0 ? "added missing patterns" : "no new patterns"}"
  end
end

puts
puts "Done."
puts "  Rules created:    #{created_rules}  (#{skipped_rules} already existed)"
puts "  Patterns created: #{created_patterns}  (#{skipped_patterns} already existed)"
db.close
