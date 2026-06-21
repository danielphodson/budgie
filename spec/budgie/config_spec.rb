require "spec_helper"
require "tmpdir"

RSpec.describe Budgie::Config do
  around do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      example.run
    end
  end

  it "loads default values when no config file exists" do
    config = described_class.load(File.join(@tmpdir, "missing.yml"))

    expect(config.db_path).to eq(File.join(Dir.home, "budgie.data", "budgie.db"))
    expect(config.backup_dir).to eq(File.join(Dir.home, "budgie.data", "backups"))
  end

  it "reads db_path and backup_dir from YAML config" do
    path = File.join(@tmpdir, "config.yml")
    File.write(path, { "db_path" => "/tmp/test.db", "backup_dir" => "/tmp/backups" }.to_yaml)

    config = described_class.load(path)

    expect(config.db_path).to eq("/tmp/test.db")
    expect(config.backup_dir).to eq("/tmp/backups")
  end

  it "uses BUDGIE_CONFIG when no explicit path is provided" do
    path = File.join(@tmpdir, "config.yml")
    File.write(path, { "db_path" => "/tmp/env.db", "backup_dir" => "/tmp/env-backups" }.to_yaml)

    ENV["BUDGIE_CONFIG"] = path
    config = described_class.load

    expect(config.db_path).to eq("/tmp/env.db")
    expect(config.backup_dir).to eq("/tmp/env-backups")
  ensure
    ENV.delete("BUDGIE_CONFIG")
  end
end
