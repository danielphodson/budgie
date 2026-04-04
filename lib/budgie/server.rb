require "sinatra/base"

module Budgie
  class Server < Sinatra::Base
    enable :method_override

    set :views,   File.join(__dir__, "views")
    set :db_path, Budgie::Database::DEFAULT_PATH

    helpers do
      def h(text)
        Rack::Utils.escape_html(text.to_s)
      end

      def repo
        db = Budgie::Database.new(db_path: settings.db_path)
        Budgie::RuleRepository.new(db)
      end
    end

    # ── Routes ────────────────────────────────────────────────────────────

    get "/" do
      redirect "/rules"
    end

    get "/rules" do
      @rules = repo.all
      erb :"rules/index"
    end

    get "/rules/new" do
      @submitted = {}
      @error     = nil
      erb :"rules/new"
    end

    post "/rules" do
      repo.create(
        name:         params["name"],
        account:      params["account"] || "",
        source_col:   params["source_col"],
        pattern:      params["pattern"],
        output_col:   params["output_col"],
        output_value: params["output_value"]
      )
      redirect "/rules"
    rescue Budgie::InvalidPattern => e
      @error     = e.message
      @submitted = params
      erb :"rules/new"
    end

    get "/rules/:id/edit" do
      @rule      = repo.find(Integer(params[:id]))
      @submitted = nil
      @error     = nil
      erb :"rules/edit"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    end

    get "/rules/:id/copy" do
      source     = repo.find(Integer(params[:id]))
      @submitted = {
        "name"         => "#{source.name} (copy)",
        "account"      => source.account,
        "source_col"   => source.source_col,
        "pattern"      => source.pattern,
        "output_col"   => source.output_col,
        "output_value" => source.output_value
      }
      @error = nil
      erb :"rules/new"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    end

    patch "/rules/:id" do
      repo.update(Integer(params[:id]), {
        name:         params["name"],
        account:      params["account"] || "",
        source_col:   params["source_col"],
        pattern:      params["pattern"],
        output_col:   params["output_col"],
        output_value: params["output_value"]
      })
      redirect "/rules"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    rescue Budgie::InvalidPattern => e
      @error     = e.message
      @submitted = params
      begin
        @rule = repo.find(Integer(params[:id]))
      rescue Budgie::RuleNotFound
        halt 404, "Rule not found"
      end
      erb :"rules/edit"
    end

    post "/rules/:id/delete" do
      repo.delete(Integer(params[:id]))
      redirect "/rules"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    end

    get "/process" do
      erb :"process"
    end

    post "/process" do
      halt 400, "No file uploaded" unless params["file"] && params["file"][:tempfile]

      upload    = params["file"]
      filename  = File.basename(upload[:filename])
      out_name  = "processed-#{filename}"

      result = Budgie::Processor.new(rule_repository: repo).process(
        input_path:  upload[:tempfile].path,
        output_path: upload[:tempfile].path + ".out"
      )

      out_data = File.read(upload[:tempfile].path + ".out")

      response.headers["Content-Disposition"] = "attachment; filename=\"#{out_name}\""
      response.headers["X-Rows-Processed"]    = result[:rows_processed].to_s
      response.headers["X-Columns-Added"]     = result[:columns_added].to_s
      content_type "text/csv"
      out_data
    ensure
      tmp_out = upload&.dig(:tempfile)&.path&.+(  ".out")
      File.delete(tmp_out) if tmp_out && File.exist?(tmp_out)
    end
  end
end
