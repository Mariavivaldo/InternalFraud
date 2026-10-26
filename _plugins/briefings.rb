# Turns the daily briefing files in _posts/ into the Fraud Board.
#
# From each day's single file it works out:
#   * the daily board and every regional brief (all on the day's page)
#   * counts in the header (incidents, sources, follow-ups, regions reporting)
#   * follow-up links between days ("Follows our coverage", "Developments since")
#     and cross-region links ("Related in another region"), from shared `story` labels
#   * the day's Tags, from the keywords of its incidents
#   * one page per keyword (/keyword/<name>/) listing every matching item, newest first
#   * one page per region (/region/<id>/) with its recent items
#   * an A-Z keyword list (/keywords/), the calendar data, and /vocabulary.json
#     (every keyword, story label and region in use, so the daily writer can reuse them)
#
# Regions need no setup: a region appears the first day a file includes it and gets the
# next color from the palette below. Optional overrides live in _data/regions.yml.

require "cgi"
require "json"
require "set"
require "time"
require_relative "../lib/briefing_validator"

module Briefing
  # Region colors from Example #11 (background, text), then extra shades for new regions.
  PALETTE = [
    { "bg" => "#D6E6F7", "fg" => "#0B3B6E" }, # blue
    { "bg" => "#FDE3D3", "fg" => "#7C2D12" }, # orange
    { "bg" => "#D3EFE8", "fg" => "#0F4D40" }, # green
    { "bg" => "#ECE3F5", "fg" => "#4A1D7A" }, # purple
    { "bg" => "#F7EBC6", "fg" => "#5C4000" }, # amber
    { "bg" => "#F6DCE6", "fg" => "#7A1F45" }, # rose
    { "bg" => "#DCE0F5", "fg" => "#2A347A" }, # indigo
    { "bg" => "#E3E3E0", "fg" => "#262626" }  # gray
  ].freeze

  REGION_HISTORY_DAYS = 30

  Day = Struct.new(:doc, :data, :date, :url, :ids, :presented)

  class Generator < Jekyll::Generator
    safe true
    priority :highest

    def generate(site)
      Builder.new(site).run
    end
  end

  class GeneratedPage < Jekyll::PageWithoutAFile
    def initialize(site, dir, name, data = {}, content = "")
      super(site, site.source, dir, name)
      self.data.merge!(data)
      self.content = content
    end
  end

  class Builder
    def initialize(site)
      @site = site
      @baseurl = site.baseurl.to_s.chomp("/")
    end

    def run
      days = load_days
      @registry = build_registry(days)
      @reg_by_id = @registry.to_h { |e| [e["id"], e] }
      @stories = Hash.new { |h, k| h[k] = [] }
      @keywords = {}
      days.each { |d| index_day(d) }
      finalize_keywords
      days.each { |d| enrich_day(d) }

      add_home(days.last)
      add_keyword_pages
      add_region_pages(days)
      add_keyword_index
      add_vocabulary(days)
      set_site_data(days)
      Jekyll.logger.info("Briefing:", "#{days.size} editions, #{@registry.size} regions, #{@keywords.size} keywords")
    end

    # ---------------------------------------------------------------- loading

    def load_days
      docs = @site.posts.docs.sort_by(&:date)
      problems = []
      days = docs.filter_map do |doc|
        res = Briefing.validate_file(doc.path)
        res.warnings.each { |w| Jekyll.logger.warn("Briefing:", "#{doc.relative_path}: #{w}") }
        if res.ok?
          Day.new(doc, res.data, res.date, doc.url, Briefing.incident_ids(res.data["incidents"]), [])
        else
          problems << ([doc.relative_path] + res.errors.map { |e| "  - #{e}" }).join("\n")
          nil
        end
      end
      days.group_by(&:date).each do |date, same|
        next if same.size < 2
        problems << "More than one briefing is dated #{date}: #{same.map { |d| d.doc.relative_path }.join(', ')}"
      end
      unless problems.empty?
        Jekyll.logger.error("Briefing:", "These briefing files need fixing before the site can be published:")
        problems.each { |p| p.each_line { |l| Jekyll.logger.error("", l.chomp) } }
        raise Jekyll::Errors::FatalException, "Briefing files have errors (listed above)."
      end
      days
    end

    def build_registry(days)
      reg = {}
      days.each do |d|
        d.data["regions"].each do |r|
          entry = (reg[r["id"]] ||= { "id" => r["id"], "index" => reg.size, "first_seen" => d.date })
          entry["name"] = r["name"].to_s.strip
        end
      end
      overrides = Array(@site.data["regions"]).select { |o| o.is_a?(Hash) && o["id"] }
      overrides.each do |o|
        e = reg[o["id"].to_s] or next
        e["name"] = o["name"].to_s.strip if o["name"]
        e["hidden"] = o["hidden"] == true
        e["bg"] = o["bg"] if o["bg"]
        e["fg"] = o["fg"] if o["fg"]
      end
      reg.each_value do |e|
        pal = PALETTE[e["index"] % PALETTE.size]
        e["bg"] ||= pal["bg"]
        e["fg"] ||= pal["fg"]
      end
      order = overrides.map { |o| o["id"].to_s }.select { |id| reg[id] }.uniq
      (order + (reg.keys - order)).map { |id| reg[id] }
    end

    def index_day(d)
      d.data["incidents"].each_with_index do |inc, i|
        ref = { "date" => d.date, "day_url" => d.url, "region" => inc["region"],
                "id" => d.ids[i], "title" => inc["title"].to_s.strip }
        @stories[inc["story"]] << ref if inc["story"]
        uniq_keywords(inc).each do |name, slug|
          kw = (@keywords[slug] ||= { "slug" => slug, "spellings" => Hash.new(0), "last_spelling" => {},
                                      "count" => 0, "dates" => Set.new, "items" => [] })
          kw["spellings"][name] += 1
          kw["last_spelling"][name] = d.date
          kw["count"] += 1
          kw["dates"] << d.date
        end
      end
    end

    # The most-used spelling of a keyword is the one shown everywhere ("Deepfake" and
    # "deepfake" are the same keyword).
    def finalize_keywords
      @keywords.each_value do |kw|
        kw["name"] = kw["spellings"].max_by { |s, n| [n, kw["last_spelling"][s]] }.first
      end
      @kw_sorted = @keywords.values.sort_by { |k| [k["name"].downcase, k["slug"]] }
    end

    # ---------------------------------------------------------------- one day

    def enrich_day(d)
      incs = d.data["incidents"].each_with_index.map { |inc, i| present_incident(d, inc, d.ids[i]) }
      d.presented = incs
      incs.each do |x|
        x["keywords"].each { |k| @keywords[k["slug"]]["items"] << [d, x] }
      end

      by_region = incs.group_by { |x| x["region"] }
      regions = @registry.filter_map do |e|
        listed = d.data["regions"].find { |r| r["id"] == e["id"] }
        next nil if e["first_seen"] > d.date      # region had not started yet
        next nil if e["hidden"] && !listed
        present_region(e, listed, by_region[e["id"]] || [])
      end

      n = incs.size
      sources = incs.sum { |x| x["source_count"] }
      follow = incs.count { |x| x["follow_up"] }
      reporting = regions.count { |r| r["has_incidents"] }
      keywords = incs.flat_map { |x| x["keywords"] }.uniq { |k| k["slug"] }.sort_by { |k| k["sort"] }

      board = {
        "date_iso" => d.date.iso8601,
        "date_long" => long_date(d.date),
        "date_short" => d.date.strftime("%a, %b %-d, %Y"),
        "url" => d.url,
        "regions" => regions,
        "region_count" => regions.size,
        "keywords" => keywords,
        "stats" => {
          "incidents" => n, "incidents_word" => n == 1 ? "incident" : "incidents",
          "sources" => sources, "sources_word" => sources == 1 ? "source" : "sources",
          "follow_ups" => follow, "follow_ups_word" => follow == 1 ? "follow-up" : "follow-ups",
          "reporting" => "#{reporting} of #{regions.size}",
          "reporting_word" => regions.size == 1 ? "region reporting" : "regions reporting"
        }
      }
      d.doc.data["board"] = board
      d.doc.data["edition_date"] = d.date.iso8601
      d.doc.data["title"] = d.data["title"].is_a?(String) ? d.data["title"] : "Briefing for #{board['date_long']}"
      d.doc.data["tags"] = (Array(d.data["tags"]).map(&:to_s) + keywords.map { |k| k["raw"] }).uniq
    end

    def present_incident(d, inc, id)
      rid = inc["region"]
      e = @reg_by_id[rid]
      sources = inc["sources"].each_with_index.map do |s, j|
        { "rank" => j + 1, "name" => h(s["name"]), "url" => h(s["url"]), "note" => h(s["note"]),
          "has_note" => !s["note"].to_s.strip.empty?, "primary" => s["primary"] == true }
      end
      thread = inc["story"] ? @stories[inc["story"]] : []
      # newest first; on the same day, this region's own coverage comes first
      prior = thread.select { |r| r["date"] < d.date }
                    .sort_by { |r| [-r["date"].jd, r["region"] == rid ? 0 : 1] }
                    .first(3).map { |r| link_ref(r, d.date, rid) }
      later = thread.select { |r| r["date"] > d.date }
                    .sort_by { |r| [r["date"].jd, r["region"] == rid ? 0 : 1] }
                    .first(3).map { |r| link_ref(r, d.date, rid) }
      related = thread.select { |r| r["date"] == d.date && r["region"] != rid }.map do |r|
        { "label" => h("#{@reg_by_id[r['region']]['name']} — #{r['title']}"), "anchor" => "#{r['region']}/#{r['id']}" }
      end
      n = sources.size
      follow = !prior.empty?
      {
        "id" => id, "region" => rid, "anchor" => "#{rid}/#{id}", "dom_id" => "inc-#{rid}-#{id}",
        "url" => "#{d.url}##{rid}/#{id}",
        "category" => h(inc["category"]), "category_upper" => h(inc["category"].to_s.strip.upcase),
        "title" => h(inc["title"]), "summary" => h(inc["summary"]), "detail" => clean_markdown(inc["detail"]),
        "keywords" => uniq_keywords(inc).map { |_, slug| keyword_link(slug) },
        "sources" => sources, "source_count" => n,
        "src_label" => "#{n} #{n == 1 ? 'SOURCE' : 'SOURCES'}#{follow ? ' · FOLLOW-UP' : ''}",
        "follow_up" => follow,
        "prior" => prior, "has_prior" => !prior.empty?,
        "later" => later, "has_later" => !later.empty?,
        "related" => related, "has_related" => !related.empty?,
        "region_name" => h(e["name"]), "region_upper" => h(e["name"].upcase), "bg" => e["bg"], "fg" => e["fg"]
      }
    end

    def present_region(e, listed, incs)
      n = incs.size
      src = incs.sum { |x| x["source_count"] }
      counts = incs.map { |x| x["category"] }.tally
      {
        "id" => e["id"], "name" => h(e["name"]), "upper" => h(e["name"].upcase), "bg" => e["bg"], "fg" => e["fg"],
        "summary" => listed ? h(listed["summary"]) : "No incidents reported today.",
        "overview" => listed ? clean_markdown(listed["overview"]) : "No incidents were reported for #{h(e['name'])} in this edition.",
        "incidents" => incs, "count" => n, "has_incidents" => n.positive?, "is_empty" => n.zero?,
        "stat_line" => "#{n} #{n == 1 ? 'incident' : 'incidents'} · #{src} #{src == 1 ? 'source' : 'sources'}",
        "breakdown" => counts.map { |k, c| "#{k} #{c}" }.join(" · "),
        "categories" => counts.keys,
        "lead" => incs.first, "others" => incs.drop(1), "no_others" => n == 1,
        "history_url" => "/region/#{e['id']}/"
      }
    end

    # ---------------------------------------------------------------- extra pages

    def add_home(latest)
      return if @site.pages.any? { |p| p.url == "/" }
      data =
        if latest
          { "layout" => "briefing", "board" => latest.doc.data["board"], "is_home" => true,
            "edition_date" => latest.date.iso8601, "title" => nil }
        else
          { "layout" => "empty", "title" => "No briefing yet" }
        end
      @site.pages << GeneratedPage.new(@site, "", "index.html", data)
    end

    def add_keyword_pages
      @keywords.each_value do |kw|
        groups = group_items(kw["items"])
        n = kw["items"].size
        list = {
          "kind" => "keyword", "eyebrow" => "KEYWORD", "heading" => h(kw["name"]),
          "meta" => "#{n} #{n == 1 ? 'item' : 'items'} across #{groups.size} #{groups.size == 1 ? 'day' : 'days'}, newest first",
          "groups" => groups, "current_slug" => kw["slug"]
        }
        @site.pages << GeneratedPage.new(@site, "keyword/#{kw['slug']}", "index.html",
                                         { "layout" => "list", "title" => "#{kw['name']} · Keyword", "list" => list })
      end
    end

    def add_region_pages(days)
      @registry.each do |e|
        pairs = days.reverse.flat_map { |d| d.presented.select { |x| x["region"] == e["id"] }.map { |x| [d, x] } }
        groups = group_items(pairs).first(REGION_HISTORY_DAYS)
        n = groups.sum { |g| g["items"].size }
        meta = groups.empty? ? "Nothing has been reported for this region yet." :
               "#{n} #{n == 1 ? 'item' : 'items'} from the last #{groups.size} #{groups.size == 1 ? 'day' : 'days'} with reports, newest first"
        list = { "kind" => "region", "eyebrow" => "REGION · RECENT DAYS", "heading" => h(e["name"]),
                 "meta" => meta, "groups" => groups, "current_slug" => nil, "bg" => e["bg"], "fg" => e["fg"] }
        @site.pages << GeneratedPage.new(@site, "region/#{e['id']}", "index.html",
                                         { "layout" => "list", "title" => "#{e['name']} · Recent days", "list" => list })
      end
    end

    def add_keyword_index
      entries = @kw_sorted.map do |k|
        keyword_link(k["slug"]).merge("count" => k["count"])
      end
      letters = entries.group_by { |k| (k["raw"][/\A[[:alpha:]]/] || "#").upcase }
                       .map { |l, ks| { "letter" => l, "keywords" => ks } }
      @site.pages << GeneratedPage.new(@site, "keywords", "index.html",
                                       { "layout" => "keywords", "title" => "All keywords",
                                         "keyword_index" => { "letters" => letters, "total" => entries.size } })
    end

    # A plain list of everything in use, for whoever writes the next day's file.
    def add_vocabulary(days)
      vocab = {
        "latest_edition" => days.last&.date&.iso8601,
        "editions" => days.size,
        "regions" => @registry.map { |e| { "id" => e["id"], "name" => e["name"], "first_seen" => e["first_seen"].iso8601 } },
        "keywords" => @kw_sorted.map do |k|
          { "keyword" => k["name"], "slug" => k["slug"], "items" => k["count"], "last_used" => k["dates"].max.iso8601 }
        end,
        "stories" => @stories.map do |id, refs|
          latest = refs.max_by { |r| r["date"] }
          { "story" => id, "first_seen" => refs.map { |r| r["date"] }.min.iso8601,
            "last_seen" => latest["date"].iso8601, "items" => refs.size,
            "latest_title" => latest["title"], "regions" => refs.map { |r| r["region"] }.uniq }
        end.sort_by { |s| [s["last_seen"], s["story"]] }.reverse
      }
      page = GeneratedPage.new(@site, "", "vocabulary.json", { "layout" => nil, "render_with_liquid" => false },
                               JSON.pretty_generate(vocab) + "\n")
      @site.pages << page
    end

    def set_site_data(days)
      max = days.map { |d| d.presented.size }.max || 0
      editions = days.map do |d|
        n = d.presented.size
        { "d" => d.date.iso8601, "u" => "#{@baseurl}#{d.url}", "n" => n,
          "s" => d.presented.sum { |x| x["source_count"] }, "l" => level(n, max) }
      end
      @site.data["briefing"] = {
        "editions" => editions,
        "keywords" => @kw_sorted.map { |k| keyword_link(k["slug"]) },
        "latest" => days.last ? days.last.date.iso8601 : nil
      }
    end

    # ---------------------------------------------------------------- helpers

    def group_items(pairs)
      pairs.group_by { |d, _| d.date }.sort_by { |date, _| date }.reverse.map do |date, ps|
        d = ps.first.first
        { "iso" => date.iso8601, "date_long" => long_date(date), "url" => d.url, "items" => ps.map(&:last) }
      end
    end

    def uniq_keywords(inc)
      inc["keywords"].map { |k| k.to_s.strip }.reject(&:empty?)
                     .map { |k| [k, Briefing.slugify(k)] }.uniq { |_, s| s }
    end

    def keyword_link(slug)
      name = @keywords[slug]["name"]
      { "name" => h(name), "raw" => name, "slug" => slug, "url" => "/keyword/#{slug}/", "sort" => name.downcase }
    end

    # "Oct 18 — Title", or "Oct 18 — Hong Kong: Title" when the item is from another region
    def link_ref(ref, current, region_id)
      short = ref["date"].year == current.year ? ref["date"].strftime("%b %-d") : ref["date"].strftime("%b %-d, %Y")
      other = ref["region"] != region_id ? "#{@reg_by_id[ref['region']]['name']}: " : ""
      short_label = other.empty? ? short : "#{short} (#{@reg_by_id[ref['region']]['name']})"
      { "label" => h("#{short} — #{other}#{ref['title']}"), "short" => h(short_label),
        "url" => "#{ref['day_url']}##{ref['region']}/#{ref['id']}" }
    end

    # Calendar shade 1-4, relative to the busiest day in the archive.
    def level(n, max)
      return 0 if n.zero? || max.zero?
      [[(n * 4.0 / max).ceil, 1].max, 4].min
    end

    def long_date(date)
      date.strftime("%A, %B %-d, %Y")
    end

    def h(text)
      CGI.escapeHTML(text.to_s.strip)
    end

    # Markdown is allowed in `detail` and `overview`; raw HTML tags are removed.
    def clean_markdown(text)
      text.to_s.gsub(%r{</?[A-Za-z!][^>]*>}, "").strip
    end
  end
end
