# Checks a daily briefing file before it is published.
#
# Used in two places:
#   * scripts/validate.rb  - run by the GitHub Actions build (and by whoever writes the
#                            daily file, before committing it)
#   * _plugins/briefings.rb - run by Jekyll while building the site
#
# Errors stop the build (so a broken file is never published). Warnings are printed
# but do not stop anything.

require "date"
require "digest"
require "yaml"

module Briefing
  SLUG = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  FILENAME = /\A(\d{4})-(\d{2})-(\d{2})-[A-Za-z0-9_-]+\.(?:md|markdown)\z/
  RESERVED_REGION_IDS = %w[board].freeze

  DAY_KEYS      = %w[date title regions incidents layout tags].freeze
  REGION_KEYS   = %w[id name summary overview].freeze
  INCIDENT_KEYS = %w[id region category title summary detail keywords story sources].freeze
  SOURCE_KEYS   = %w[name url note primary].freeze

  Result = Struct.new(:path, :date, :data, :errors, :warnings) do
    def ok?
      errors.empty?
    end
  end

  module_function

  # "Bank of America" -> "bank-of-america"; "Société Générale" -> "societe-generale"
  def slugify(text)
    s = text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
    s = s.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    s.empty? ? "kw-#{Digest::MD5.hexdigest(text.to_s)[0, 8]}" : s
  end

  # Gives every incident a unique id within the day. An explicit `id` is kept as-is;
  # otherwise the id comes from the title (with -2, -3 ... added if two titles match).
  def incident_ids(incidents)
    used = {}
    incidents.map do |inc|
      next nil unless inc.is_a?(Hash)
      base = inc["id"].is_a?(String) && !inc["id"].empty? ? inc["id"] : slugify(inc["title"]).sub(/\Akw-/, "item-")
      id = base
      n = 2
      while used[id]
        id = "#{base}-#{n}"
        n += 1
      end
      used[id] = true
      id
    end
  end

  def front_matter(text)
    m = text.match(/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\z)/m)
    m && m[1]
  end

  def to_date(value)
    case value
    when Date then value
    when Time then value.to_date
    when String then (Date.parse(value) rescue nil)
    end
  end

  def validate_file(path)
    errors = []
    warnings = []
    base = File.basename(path)
    date = nil

    if (m = FILENAME.match(base))
      begin
        date = Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
      rescue ArgumentError
        errors << "the file name has an impossible date (#{base})"
      end
    else
      errors << "the file name must look like YYYY-MM-DD-briefing.md (got #{base})"
    end

    text = File.read(path, encoding: "UTF-8")
    raw = front_matter(text)
    data = nil
    if raw.nil?
      errors << "the file must start with front matter between two '---' lines"
    else
      begin
        data = YAML.safe_load(raw, permitted_classes: [Date, Time], aliases: false)
      rescue Psych::SyntaxError => e
        # +1 because the front matter starts on the second line of the file
        errors << "the YAML could not be read at line #{e.line + 1}, column #{e.column}: #{e.problem} #{e.context}".strip
      rescue Psych::Exception => e
        errors << "the YAML could not be read: #{e.message}"
      end
    end

    validate_data(data, date, errors, warnings) if raw && errors.none? { |er| er.start_with?("the YAML") }
    Result.new(path, date, data, errors, warnings)
  end

  def validate_data(data, date, errors, warnings)
    unless data.is_a?(Hash)
      errors << "the front matter must be a set of 'field: value' lines"
      return
    end
    (data.keys - DAY_KEYS).each { |k| warnings << "unknown top-level field '#{k}' (ignored)" }

    if data.key?("date") && date
      fd = to_date(data["date"])
      if fd.nil?
        errors << "date: '#{data['date']}' is not a date"
      elsif fd != date
        errors << "date: #{fd} does not match the date in the file name (#{date})"
      end
    end

    region_ids = validate_regions(data["regions"], errors, warnings)
    validate_incidents(data["incidents"], region_ids, errors, warnings)
  end

  def validate_regions(regions, errors, warnings)
    ids = []
    if !regions.is_a?(Array) || regions.empty?
      errors << "regions: must be a list with at least one region"
      return ids
    end
    regions.each_with_index do |r, i|
      at = "regions[#{i}]"
      unless r.is_a?(Hash)
        errors << "#{at}: must be a set of fields (id, name, summary, overview)"
        next
      end
      at = "regions[#{i}] (#{r['id']})" if r["id"].is_a?(String)
      (r.keys - REGION_KEYS).each { |k| warnings << "#{at}: unknown field '#{k}' (ignored)" }
      id = r["id"]
      if !id.is_a?(String) || id !~ SLUG
        errors << "#{at}.id: must be lowercase letters, digits and hyphens, like 'us' or 'new-york' (got #{id.inspect})"
      elsif RESERVED_REGION_IDS.include?(id)
        errors << "#{at}.id: '#{id}' is reserved by the site; pick another id"
      elsif ids.include?(id)
        errors << "#{at}.id: '#{id}' is listed twice"
      else
        ids << id
      end
      %w[name summary overview].each { |k| require_text(r, k, at, errors) }
    end
    ids
  end

  def validate_incidents(incidents, region_ids, errors, warnings)
    if incidents.nil?
      errors << "incidents: missing (write 'incidents: []' for a day with no incidents)"
      return
    end
    unless incidents.is_a?(Array)
      errors << "incidents: must be a list"
      return
    end

    explicit_ids = Hash.new { |h, k| h[k] = [] }
    incidents.each_with_index do |inc, i|
      at = "incidents[#{i}]"
      unless inc.is_a?(Hash)
        errors << "#{at}: must be a set of fields"
        next
      end
      at = "#{at} (\"#{truncate(inc['title'])}\")" if inc["title"].is_a?(String)
      (inc.keys - INCIDENT_KEYS).each { |k| warnings << "#{at}: unknown field '#{k}' (ignored)" }
      %w[title summary detail category].each { |k| require_text(inc, k, at, errors) }

      reg = inc["region"]
      if !reg.is_a?(String) || reg.strip.empty?
        errors << "#{at}.region: missing"
      elsif !region_ids.include?(reg)
        errors << "#{at}.region: '#{reg}' is not one of the regions listed in this file (#{region_ids.join(', ')})"
      end

      if inc.key?("id")
        if !inc["id"].is_a?(String) || inc["id"] !~ SLUG
          errors << "#{at}.id: must be lowercase letters, digits and hyphens"
        else
          explicit_ids[inc["id"]] << at
        end
      end

      story = inc["story"]
      if !story.nil? && (!story.is_a?(String) || story !~ SLUG)
        errors << "#{at}.story: must be lowercase letters, digits and hyphens, like 'exec-voice-impersonation'"
      end

      validate_keywords(inc["keywords"], at, errors, warnings)
      validate_sources(inc["sources"], at, errors, warnings)
    end

    explicit_ids.each do |id, places|
      next if places.size < 2
      errors << "incident id '#{id}' is used more than once: #{places.join('; ')}"
    end
  end

  def validate_keywords(kws, at, errors, warnings)
    if !kws.is_a?(Array) || kws.empty?
      errors << "#{at}.keywords: must be a list with at least one keyword"
      return
    end
    kws.each_with_index do |k, j|
      unless (k.is_a?(String) || k.is_a?(Numeric)) && !k.to_s.strip.empty?
        errors << "#{at}.keywords[#{j}]: must be a word or phrase"
      end
    end
    dups = kws.map { |k| slugify(k) }.tally.select { |_, n| n > 1 }.keys
    warnings << "#{at}.keywords: the same keyword is listed twice (#{dups.join(', ')})" unless dups.empty?
  end

  def validate_sources(srcs, at, errors, warnings)
    if !srcs.is_a?(Array) || srcs.empty?
      errors << "#{at}.sources: must be a list with at least one source"
      return
    end
    srcs.each_with_index do |s, j|
      sat = "#{at}.sources[#{j}]"
      unless s.is_a?(Hash)
        errors << "#{sat}: must be a set of fields (name, url, note)"
        next
      end
      (s.keys - SOURCE_KEYS).each { |k| warnings << "#{sat}: unknown field '#{k}' (ignored)" }
      require_text(s, "name", sat, errors)
      url = s["url"]
      unless url.is_a?(String) && url.match?(%r{\Ahttps?://[^\s/]+\.[^\s]+\z})
        errors << "#{sat}.url: must be a full web address starting with https:// (got #{url.inspect})"
      end
      if !s["note"].is_a?(String) || s["note"].strip.empty?
        warnings << "#{sat}.note: missing (the note explains why the source ranks where it does)"
      end
      if s.key?("primary") && ![true, false].include?(s["primary"])
        errors << "#{sat}.primary: must be true or false"
      end
    end
  end

  def require_text(hash, key, at, errors)
    v = hash[key]
    return if (v.is_a?(String) && !v.strip.empty?) || v.is_a?(Numeric)
    errors << (v.nil? ? "#{at}.#{key}: missing" : "#{at}.#{key}: must be text")
  end

  def truncate(text, max = 48)
    t = text.to_s.strip
    t.length > max ? "#{t[0, max - 1]}…" : t
  end
end
