# budgie

A Ruby gem that augments CSV files by applying rules stored in a SQLite database. Each rule matches column values against patterns and appends new columns to matching rows.

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

You define **rules**. Each rule specifies an output (a column name and value to write) and one or more **patterns** that trigger it.

| Field | Description |
|---|---|
| **Name** | A human-readable label for the rule |
| **Account** | Optional label written to the `account` column in the output |
| **Output column** | The column name to append to the output CSV |
| **Output value** | The value to write in that column when the rule matches |

Each **pattern** within a rule specifies:

| Field | Description |
|---|---|
| **Source column** | The CSV column header to match against |
| **Pattern** | A case-insensitive substring to look for in that column |

A rule fires when **any** of its patterns matches. This lets you group related transactions under one output value — for example, a "Mortgage" rule with patterns for "Loan repayment" and "Debit interest".

When you process a CSV, budgie evaluates every rule against every row. Matching rules append their output columns to the row. The `account` column (if any rule sets it) always appears first among the appended columns.

## Web UI

The easiest way to manage rules and process files is via the built-in web interface.

### Quick Start

For local development:

```sh
bundle exec exe/budgie server start
```

For remote access (allows connections from other machines):

```sh
bundle exec exe/budgie server start --host 0.0.0.0
```

### Production Service

For production deployment, use the provided control script:

```sh
# Start the server
./bin/budgie-server start

# Stop the server
./bin/budgie-server stop

# Restart the server
./bin/budgie-server restart
```

You can customize the host and port with environment variables:

```sh
BUDGIE_HOST=127.0.0.1 BUDGIE_PORT=8080 ./bin/budgie-server start
```

### Systemd Service (Recommended for Production)

For automatic startup and management, install as a systemd service:

```sh
sudo cp budgie.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable budgie
sudo systemctl start budgie
```

Manage the service:

```sh
sudo systemctl status budgie        # Check status
sudo systemctl restart budgie       # Restart
sudo journalctl -u budgie -f        # View logs
```

See [SYSTEMD_SETUP.md](SYSTEMD_SETUP.md) for detailed instructions.

Then open [http://localhost:4567](http://localhost:4567) in your browser (or your server's hostname/port for remote access).

**Options:**

```sh
budgie server start --port 8080          # use a different port
budgie server start --db /path/to/my.db  # use a specific database file
```

The web UI has two sections:

- **Rules** — create, edit, copy, and delete rules; add and remove individual patterns per rule
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

**Add a rule** (with an initial pattern):

```sh
budgie rules add \
  --name "Groceries" \
  --account "Visa" \
  --source-col "Description" \
  --pattern "whole foods" \
  --output-col "Category" \
  --output-value "Groceries"
```

`--account` is optional. The pattern is a plain text substring — matching is always case-insensitive. Additional patterns can be added via the web UI or by editing the YAML.

**Edit a rule** (opens `$EDITOR` with a YAML file including a `patterns` list):

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

And a rule with output column `Category`, output value `Groceries`, account `Visa`, and patterns `tesco` and `whole foods` (both matching the `Description` column):

Running `budgie process transactions.csv out.csv` produces:

```
Date,Description,Amount,account,Category
2024-01-05,Tesco Superstore,45.20,Visa,Groceries
2024-01-06,Shell Petrol,60.00,,
2024-01-07,Whole Foods Market,32.10,Visa,Groceries
```

## Seeding rules from a categorised CSV

If you already have a CSV with a `Category` (or `CATEGORY`) column, you can bootstrap your rules automatically:

```sh
bundle exec ruby scripts/seed_rules.rb path/to/transactions.csv
```

The script reads the `Other Party` and `Category` columns and creates one rule per category. Each unique value in `Other Party` becomes a pattern on that rule. Re-running is safe — existing rules and patterns are skipped, only new ones are added.

## Database

By default the SQLite database is stored at `~/budgie.data/budgie.db`. It is created automatically on first run.

### Configuration

Create `~/.budgie/config.yml` with optional values for `db_path` and `backup_dir`:

```yaml
db_path: /home/you/budgie.data/budgie.db
backup_dir: /home/you/budgie.data/backups
```

Both `budgie server start` and `ruby scripts/backup_database.rb` will use the values in that file when the parameters are not provided explicitly.

You can still override the database path on startup:

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
- Dependencies: `thor`, `sqlite3`, `csv`, `sinatra`, `rackup`
