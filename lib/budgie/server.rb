require "sinatra/base"

module Budgie
  class Server < Sinatra::Base
    set :environment, :production
    enable :method_override

    set :views,   File.join(__dir__, "views")
    set :db_path, Budgie::Database::DEFAULT_PATH

    helpers do
      def h(text)
        Rack::Utils.escape_html(text.to_s)
      end

      def repo
        db = Budgie::Database.new(db_path: settings.db_path)
        Budgie::CategoryRepository.new(db)
      end

      def transaction_repo
        db = Budgie::Database.new(db_path: settings.db_path)
        Budgie::TransactionRepository.new(db)
      end

      def transaction_processor(trepo)
        Budgie::TransactionProcessor.new(category_repository: repo, transaction_repository: trepo)
      end

      def adjacent_month(year_month, delta)
        return nil unless year_month
        y, m = year_month.split("-").map(&:to_i)
        m += delta
        if m > 12
          m = 1; y += 1
        elsif m < 1
          m = 12; y -= 1
        end
        "#{y}-#{m.to_s.rjust(2, '0')}"
      end

      MONTH_NAMES = %w[January February March April May June July August September October November December].freeze

      def format_month(year_month)
        return "" unless year_month
        y, m = year_month.split("-").map(&:to_i)
        "#{MONTH_NAMES[m - 1]} #{y}"
      end
    end

    # ── Routes ────────────────────────────────────────────────────────────

    get "/" do
      redirect "/categories"
    end

    get "/rules" do
      redirect "/categories"
    end

    get "/categories" do
      @categories = repo.all
      erb :"rules/index"
    end

    get "/rules/new" do
      redirect "/categories/new"
    end

    get "/categories/new" do
      @show_rule_fields = params["source_col"] || params["pattern"]
      @submitted  = {
        "output_value"   => params["output_value"]   || "",
        "monthly_budget" => params["monthly_budget"] || "",
        "kind"           => params["kind"]           || "expense",
        "source_col"     => params["source_col"]     || (@show_rule_fields ? "Other Party" : "Other Party"),
        "pattern"        => params["pattern"]        || ""
      }
      @categories      = repo.all.map(&:output_value).uniq.sort
      @return_month    = params["month"]
      @return_category = params["category"].to_s
      @error           = nil
      erb :"rules/new"
    end

    post "/categories" do
      @return_month    = params["month"]
      @return_category = params["category"].to_s
      r                = repo
      existing         = r.all.find { |category| category.output_value == params["output_value"] }
      rule_source      = params["source_col"].to_s
      rule_pattern     = params["pattern"].to_s
      show_rule_fields = params.key?("source_col") || params.key?("pattern")
      has_rule         = !rule_pattern.strip.empty?

      raise Budgie::InvalidPattern, "Pattern cannot be empty" if show_rule_fields && !has_rule

      if existing
        if has_rule
          r.add_rule(existing.id, source_col: rule_source, pattern: rule_pattern)
          transaction_processor(transaction_repo).reprocess_all
          redirect_url = "/transactions"
          query = []
          query << "month=#{Rack::Utils.escape(@return_month)}" if @return_month && !@return_month.empty?
          query << "category=#{Rack::Utils.escape(@return_category)}" if @return_category && !@return_category.empty?
          redirect redirect_url + (query.empty? ? "" : "?#{query.join("&")}")
        else
          redirect "/categories/#{existing.id}/edit"
        end
      else
        budget = params["monthly_budget"].to_s.strip
        rules = has_rule ? [{ source_col: rule_source, pattern: rule_pattern }] : []
        r.create(
          name:           params["output_value"],
          account:        "",
          output_col:     "Category",
          output_value:   params["output_value"],
          monthly_budget: budget.empty? ? nil : budget.to_f,
          kind:           params["kind"] == "income" ? "income" : "expense",
          rules:          rules
        )

        transaction_processor(transaction_repo).reprocess_all
        redirect_url = "/transactions"
        query = []
        query << "month=#{Rack::Utils.escape(@return_month)}" if @return_month && !@return_month.empty?
        query << "category=#{Rack::Utils.escape(@return_category)}" if @return_category && !@return_category.empty?
        redirect redirect_url + (query.empty? ? "" : "?#{query.join("&")}")
      end
    rescue Budgie::InvalidPattern => e
      @error           = e.message
      @show_rule_fields = params.key?("source_col") || params.key?("pattern")
      @submitted       = params
      @categories      = repo.all.map(&:output_value).uniq.sort
      erb :"rules/new"
    end

    get "/rules/:id/edit" do
      redirect "/categories/#{params[:id]}/edit"
    end

    get "/categories/:id/edit" do
      @category  = repo.find(Integer(params[:id]))
      @rule      = @category
      @error     = nil
      erb :"rules/edit"
    rescue Budgie::CategoryNotFound
      halt 404, "Category not found"
    end

    get "/rules/:id/copy" do
      redirect "/categories/#{params[:id]}/copy"
    end

    get "/categories/:id/copy" do
      source     = repo.find(Integer(params[:id]))
      @category  = source
      @rule      = source
      @submitted = {
        "output_value" => source.output_value,
        "source_col"   => source.rules.first&.source_col.to_s,
        "pattern"      => source.rules.first&.pattern.to_s
      }
      @error = nil
      erb :"rules/new"
    rescue Budgie::CategoryNotFound
      halt 404, "Category not found"
    end

    patch "/categories/:id" do
      budget = params["monthly_budget"].to_s.strip
      repo.update(Integer(params[:id]), {
        name:           params["output_value"],
        account:        "",
        output_col:     "Category",
        output_value:   params["output_value"],
        monthly_budget: budget.empty? ? nil : budget.to_f,
        kind:           params["kind"] == "income" ? "income" : "expense"
      })
      redirect "/categories"
    rescue Budgie::CategoryNotFound
      halt 404, "Category not found"
    end

    post "/categories/:id/delete" do
      repo.delete(Integer(params[:id]))
      redirect "/categories"
    rescue Budgie::CategoryNotFound
      halt 404, "Category not found"
    end

    # ── Rules ───────────────────────────────────────────────────────────

    post "/categories/:id/rules" do
      repo.add_rule(
        Integer(params[:id]),
        source_col: params["source_col"],
        pattern:    params["pattern"]
      )
      redirect "/categories/#{params[:id]}/edit"
    rescue Budgie::CategoryNotFound
      halt 404, "Category not found"
    rescue Budgie::InvalidPattern => e
      @category  = repo.find(Integer(params[:id]))
      @rule      = @category
      @error = e.message
      erb :"rules/edit"
    end

    post "/categories/:id/rules/:rule_id/delete" do
      repo.delete_rule(Integer(params[:rule_id]))
      redirect "/categories/#{params[:id]}/edit"
    rescue Budgie::CategoryNotFound
      halt 404, "Rule not found"
    end

    # ── Tracking ─────────────────────────────────────────────────────────

    get "/tracking" do
      require "json"
      trepo  = transaction_repo
      months = trepo.available_months
      @month      = params["month"] || months.first
      @months     = months
      @prev_month = adjacent_month(@month, -1)
      @next_month = adjacent_month(@month,  1)

      rules          = repo.all
      transactions   = @month ? trepo.for_month(@month) : []

      # Count and sum amounts by effective category for the month
      totals               = Hash.new(0.0)
      uncategorized_count  = 0
      transactions.each do |t|
        extras = t["processed_data"] ? JSON.parse(t["processed_data"]) : {}
        cat    = t["manual_category"] || extras["Category"]
        uncategorized_count += 1 if cat.nil?
        totals[cat || :uncategorized] += t["amount"]
      end
      @uncategorized_count = uncategorized_count

      # Build lookup: output_value -> { budget, kind }
      rule_meta = rules.each_with_object({}) do |r, h|
        h[r.output_value] ||= { budget: r.monthly_budget, kind: r.kind }
      end

      remaining_totals = totals.dup

      rows = rule_meta.keys.sort.map do |cat|
        meta = rule_meta[cat]
        { category: cat, budget: meta[:budget], kind: meta[:kind], spent: remaining_totals.delete(cat) || 0.0 }
      end

      # Categories in transactions with no matching rule default to expense
      remaining_totals.each do |cat, spent|
        next if cat == :uncategorized
        rows << { category: cat, budget: nil, kind: "expense", spent: spent }
      end
      rows.sort_by! { |r| r[:category] }

      if (unc = remaining_totals[:uncategorized])
        rows << { category: nil, budget: nil, kind: "expense", spent: unc }
      end

      @expense_rows    = rows.select { |r| r[:kind] == "expense" && r[:budget].to_f > 0 }
      @income_rows     = rows.select { |r| r[:kind] == "income"  && r[:budget].to_f > 0 }
      @unbudgeted_rows = rows.select { |r| r[:budget].to_f == 0 }

      erb :"tracking/index"
    end

    # ── Transactions ─────────────────────────────────────────────────────

    get "/transactions" do
      require "json"
      trepo         = transaction_repo
      months        = trepo.available_months
      @month        = params["month"] || months.first
      all_for_month = @month ? trepo.for_month(@month) : []
      @months       = months
      @prev_month   = adjacent_month(@month, -1)
      @next_month   = adjacent_month(@month,  1)
      @imported         = params["imported"]
      @category_filter  = params["category"].to_s

      rule_cats = repo.all.map(&:output_value)
      txn_cats  = all_for_month.flat_map { |t|
        extras = t["processed_data"] ? JSON.parse(t["processed_data"]) : {}
        [t["manual_category"], extras["Category"]].compact
      }
      @categories = (rule_cats + txn_cats).uniq.sort

      @transactions = if @category_filter.empty?
        all_for_month
      elsif @category_filter == "__uncategorized__"
        all_for_month.select { |t|
          extras = t["processed_data"] ? JSON.parse(t["processed_data"]) : {}
          (t["manual_category"] || extras["Category"]).nil?
        }
      else
        all_for_month.select { |t|
          extras = t["processed_data"] ? JSON.parse(t["processed_data"]) : {}
          (t["manual_category"] || extras["Category"]) == @category_filter
        }
      end

      erb :"transactions/index"
    end

    get "/transactions/upload" do
      erb :"transactions/upload"
    end

    post "/transactions" do
      halt 400, "No file uploaded"    unless params["file"] && params["file"][:tempfile]
      halt 400, "No account selected" unless params["account"] && !params["account"].empty?

      trepo = transaction_repo
      count = Budgie::TransactionImporter.new(transaction_repository: trepo).import(
        path:    params["file"][:tempfile].path,
        account: params["account"]
      )
      transaction_processor(trepo).reprocess_all
      redirect "/transactions?imported=#{count}"
    end

    post "/transactions/reprocess" do
      trepo = transaction_repo
      transaction_processor(trepo).reprocess_all
      redirect "/transactions"
    end

    post "/transactions/:id/category" do
      content_type :json
      category = params["category"].to_s.strip
      transaction_repo.set_manual_category(Integer(params[:id]), category.empty? ? nil : category)
      "{}"
    end

  end
end
