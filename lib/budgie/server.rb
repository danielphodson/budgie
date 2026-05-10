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
        Budgie::RuleRepository.new(db)
      end

      def transaction_repo
        db = Budgie::Database.new(db_path: settings.db_path)
        Budgie::TransactionRepository.new(db)
      end

      def transaction_processor(trepo)
        Budgie::TransactionProcessor.new(rule_repository: repo, transaction_repository: trepo)
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
      redirect "/rules"
    end

    get "/rules" do
      @rules = repo.all
      erb :"rules/index"
    end

    get "/rules/new" do
      @submitted  = {
        "source_col"     => params["source_col"]     || "Other Party",
        "pattern"        => params["pattern"]        || "",
        "output_value"   => params["output_value"]   || "",
        "monthly_budget" => params["monthly_budget"] || "",
        "kind"           => params["kind"]           || "expense"
      }
      @categories = repo.all.map(&:output_value).uniq.sort
      @error      = nil
      erb :"rules/new"
    end

    post "/rules" do
      r        = repo
      existing = r.all.find { |rule| rule.output_value == params["output_value"] }

      if existing
        r.add_pattern(existing.id, source_col: params["source_col"], pattern: params["pattern"])
        redirect "/rules/#{existing.id}/edit"
      else
        budget = params["monthly_budget"].to_s.strip
        r.create(
          name:           params["output_value"],
          account:        "",
          output_col:     "Category",
          output_value:   params["output_value"],
          monthly_budget: budget.empty? ? nil : budget.to_f,
          kind:           params["kind"] == "income" ? "income" : "expense",
          patterns:       [{ source_col: params["source_col"], pattern: params["pattern"] }]
        )
        redirect "/rules"
      end
    rescue Budgie::InvalidPattern => e
      @error     = e.message
      @submitted = params
      @categories = repo.all.map(&:output_value).uniq.sort
      erb :"rules/new"
    end

    get "/rules/:id/edit" do
      @rule      = repo.find(Integer(params[:id]))
      @error     = nil
      erb :"rules/edit"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    end

    get "/rules/:id/copy" do
      source     = repo.find(Integer(params[:id]))
      @submitted = {
        "output_value" => source.output_value,
        "source_col"   => source.patterns.first&.source_col.to_s,
        "pattern"      => source.patterns.first&.pattern.to_s
      }
      @error = nil
      erb :"rules/new"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    end

    patch "/rules/:id" do
      budget = params["monthly_budget"].to_s.strip
      repo.update(Integer(params[:id]), {
        name:           params["output_value"],
        account:        "",
        output_col:     "Category",
        output_value:   params["output_value"],
        monthly_budget: budget.empty? ? nil : budget.to_f,
        kind:           params["kind"] == "income" ? "income" : "expense"
      })
      redirect "/rules"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    end

    post "/rules/:id/delete" do
      repo.delete(Integer(params[:id]))
      redirect "/rules"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    end

    # ── Pattern routes ────────────────────────────────────────────────────

    post "/rules/:id/patterns" do
      repo.add_pattern(
        Integer(params[:id]),
        source_col: params["source_col"],
        pattern:    params["pattern"]
      )
      redirect "/rules/#{params[:id]}/edit"
    rescue Budgie::RuleNotFound
      halt 404, "Rule not found"
    rescue Budgie::InvalidPattern => e
      @rule  = repo.find(Integer(params[:id]))
      @error = e.message
      erb :"rules/edit"
    end

    post "/rules/:id/patterns/:pattern_id/delete" do
      repo.delete_pattern(Integer(params[:pattern_id]))
      redirect "/rules/#{params[:id]}/edit"
    rescue Budgie::RuleNotFound
      halt 404, "Pattern not found"
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

      rules        = repo.all
      transactions = @month ? trepo.for_month(@month) : []

      # Sum amounts by effective category for the month
      totals = Hash.new(0.0)
      transactions.each do |t|
        extras = t["processed_data"] ? JSON.parse(t["processed_data"]) : {}
        cat    = t["manual_category"] || extras["Category"]
        totals[cat || :uncategorized] += t["amount"]
      end

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
