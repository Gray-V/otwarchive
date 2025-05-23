class TagQuery < Query

  def klass
    'Tag'
  end

  def index_name
    TagIndexer.index_name
  end

  def document_type
    TagIndexer.document_type
  end

  def filters
    [
      type_filter,
      wrangling_status_filter,
      unwrangleable_filter,
      posted_works_filter,
      media_filter,
      fandom_filter,
      character_filter,
      suggested_fandom_filter,
      suggested_character_filter,
      in_use_filter,
      unwrangled_filter
    ].flatten.compact
  end

  def exclusion_filters
    [
      wrangled_filter
    ].compact
  end

  def queries
    [name_query].compact
  end

  # Tags have a different default per_page value:
  def per_page
    options[:per_page] || ArchiveConfig.TAGS_PER_SEARCH_PAGE || 50
  end

  def sort
    direction = options[:sort_direction]&.downcase
    case options[:sort_column]
    when "taggings_count_cache", "uses"
      column = "uses"
      direction ||= "desc"
    when "created_at"
      column = "created_at"
      direction ||= "desc"
    else
      column = "name.keyword"
      direction ||= "asc"
    end
    sort_hash = { column => { order: direction } }

    if column == "created_at"
      sort_hash[column][:unmapped_type] = "date"
    end

    sort_by_id = { id: { order: direction } }

    return [sort_hash, { "name.keyword" => { order: "asc" } }, sort_by_id] if column == "uses"

    [sort_hash, sort_by_id]
  end

  ################
  # FILTERS
  ################

  def type_filter
    { term: { tag_type: options[:type] } } if options[:type]
  end

  def wrangling_status_filter
    case options[:wrangling_status]
    when "canonical"
      term_filter(:canonical, true)
    when "noncanonical"
      term_filter(:canonical, false)
    when "synonymous"
      [exists_filter("merger_id"), term_filter(:canonical, false)]
    when "canonical_synonymous"
      { bool: { should: [exists_filter("merger_id"), term_filter(:canonical, true)] } }
    when "noncanonical_nonsynonymous"
      [{ bool: { must_not: exists_filter("merger_id") } }, term_filter(:canonical, false)]
    end
  end

  def unwrangleable_filter
    term_filter(:unwrangleable, bool_value(options[:unwrangleable])) unless options[:unwrangleable].nil?
  end

  def posted_works_filter
    term_filter(:has_posted_works, bool_value(options[:has_posted_works])) unless options[:has_posted_works].nil?
  end

  def media_filter
    terms_filter(:media_ids, options[:media_ids]) if options[:media_ids]
  end

  def fandom_filter
    options[:fandom_ids]&.map { |fandom_id| term_filter(:fandom_ids, fandom_id) }
  end

  def character_filter
    terms_filter(:character_ids, options[:character_ids]) if options[:character_ids]
  end

  def suggested_fandom_filter
    terms_filter(:pre_fandom_ids, options[:pre_fandom_ids]) if options[:pre_fandom_ids]
  end

  def suggested_character_filter
    terms_filter(:pre_character_ids, options[:pre_character_ids]) if options[:pre_character_ids]
  end

  # Canonical tags are treated as used even if they technically aren't
  def in_use_filter
    return if options[:in_use].nil?

    unless options[:in_use]
      # Check if not used AND not canonical
      return [term_filter(:uses, 0), term_filter(:canonical, false)]
    end

    # Check if used OR canonical
    { bool: { should: [{ range: { uses: { gt: 0 } } }, term_filter(:canonical, true)] } }
  end

  def unwrangled_filter
    term_filter(:unwrangled, bool_value(options[:unwrangled])) unless options[:unwrangled].nil?
  end

  # Filter to only include tags that have no assigned fandom_ids. Checks that
  # the fandom exists, because this particular filter is included in the
  # exclusion_filters section.
  def wrangled_filter
    exists_filter("fandom_ids") unless options[:wrangled].nil?
  end

  ################
  # QUERIES
  ################

  def name_query
    return unless options[:name]
    {
      query_string: {
        query: escape_reserved_characters(options[:name]),
        fields: ["name.exact^2", "name"],
        default_operator: "and"
      }
    }
  end
end
