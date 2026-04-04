require_relative "lib/budgie/version"

Gem::Specification.new do |spec|
  spec.name          = "budgie"
  spec.version       = Budgie::VERSION
  spec.authors       = ["Daniel"]
  spec.summary       = "CSV augmentation via regex-matched rules stored in SQLite"
  spec.license       = "MIT"
  spec.require_paths = ["lib"]
  spec.executables   = ["budgie"]
  spec.files         = Dir["lib/**/*", "exe/*", "LICENSE", "README.md"]

  spec.required_ruby_version = ">= 3.1"

  spec.add_dependency "thor",    "~> 1.5"
  spec.add_dependency "sqlite3", "~> 2.0"
  spec.add_dependency "csv",     "~> 3.0"
  spec.add_dependency "sinatra", "~> 4.0"
end
