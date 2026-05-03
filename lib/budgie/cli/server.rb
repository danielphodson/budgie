require "thor"

module Budgie
  module CLI
    class Server < Thor
      desc "start", "Start the Budgie web UI"
      option :port, type: :numeric, default: 4567, aliases: "-p",
                    desc: "Port to listen on"
      option :host, type: :string,  default: "localhost", aliases: "-H",
                    desc: "Host to bind to (use 0.0.0.0 to allow remote access)"
      option :db,   type: :string,  default: Budgie::Database::DEFAULT_PATH, aliases: "-d",
                    desc: "Path to the SQLite database file"
      def start
        Budgie::Server.set(:db_path, options[:db])
        Budgie::Server.set(:port, options[:port])
        Budgie::Server.set(:bind, options[:host])
        Budgie::Server.set(:protection, except: :host_authorization) if options[:host] != "localhost"
        Budgie::Server.set(:logging, false)
        say "Starting Budgie web UI at http://#{options[:host]}:#{options[:port]}"
        say "Database: #{options[:db]}"
        say "Press Ctrl+C to stop."
        Budgie::Server.run!
      end
    end
  end
end
