# budgie

A Ruby gem that augments CSV files by applying regex-based rules stored in a SQLite database. Each rule matches a column value against a pattern and appends new columns to matching rows.

## Installation

Clone the repo and install dependencies:

```sh
git clone git@github.com:danielphodson/budgie.git
cd budgie
bundle install
```

Make the CLI executable available:

```sh
bundle exec exe/budgie
```

Or install the gem locally:

```sh
gem build budgie.gemspec
gem install budgie-0.1.0.gem
```

## How it works

You define **rules**, each specifying:

| Field | Description |
|---|---|
| **Name** | A human-readable label for the rule |
| **Account** | Optional label written to the `account` column in the output |
| **Source column** | The CSV column header to match against |
| **Pattern** | A Ruby regex (without delimiters) matched against the source column value |
| **Output column** | The column name to append to the output CSV |
| **Output value** | The value to write in that column when the rule matches |

When you process a CSV, budgie evaluates every rule against every row. Matching rules append their output columns to the row. The `account` column (if any rule sets it) always appears first among the appended columns.

## Web UI

The easiest way to manage rules and process files is via the built-in web interface:

```sh
budgie server start
```

Then open [http://localhost:4567](http://localhost:4567) in your browser.

**Options:**

```sh
budgie server start --port 8080          # use a different port
budgie server start --db /path/to/my.db  # use a specific database file
```

The web UI has two sections:

- **Rules** — create, edit, copy, and delete rules
- **Process** — drag and drop (or select) a CSV file, click Process, and the augmented file downloads automatically as `processed-<original-name>.csv`

## CLI

### Processing a CSV

```sh
budgie process input.csv output.csv
```

Reads `input.csv`, applies all rules, and writes the augmented rows to `output.csv`.

### Managing rules

**List all rules:**

```sh
budgie rules list
```

**Add a rule:**

```sh
budgie rules add \
  --name "Groceries" \
  --account "Visa" \
  --source-col "Description" \
  --pattern "(?i)whole foods|tesco|sainsbury" \
  --output-col "Category" \
  --output-value "Groceries"
```

`--account` is optional. The pattern is a Ruby regex without delimiters — use `(?i)` for case-insensitive matching.

**Edit a rule** (opens `$EDITOR` with a YAML file):

```sh
budgie rules edit 3
```

**Delete a rule:**

```sh
budgie rules delete 3
```

### Example

Given `transactions.csv`:

```
Date,Description,Amount
2024-01-05,Tesco Superstore,45.20
2024-01-06,Shell Petrol,60.00
2024-01-07,Whole Foods Market,32.10
```

And a rule: source column `Description`, pattern `(?i)tesco|whole foods`, output column `Category`, output value `Groceries`, account `Visa`:

Running `budgie process transactions.csv out.csv` produces:

```
Date,Description,Amount,account,Category
2024-01-05,Tesco Superstore,45.20,Visa,Groceries
2024-01-06,Shell Petrol,60.00,,
2024-01-07,Whole Foods Market,32.10,Visa,Groceries
```

## Database

By default the SQLite database is stored at `~/.budgie/budgie.db`. It is created automatically on first run. You can point budgie at a different file with `--db`:

```sh
budgie server start --db ~/Documents/my-budget.db
```

## Development

Run the test suite:

```sh
bundle exec rspec
```

## Requirements

- Ruby >= 3.1
- Dependencies: `thor`, `sqlite3`, `csv`, `sinatra`
