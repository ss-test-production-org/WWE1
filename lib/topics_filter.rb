# frozen_string_literal: true

class TopicsFilter
  attr_reader :topic_notification_levels

  def initialize(guardian:, scope: Topic.all)
    @guardian = guardian
    @scope = scope
    @topic_notification_levels = Set.new
  end

  FILTER_ALIASES = { "categories" => "category" }
  private_constant :FILTER_ALIASES

  def filter_from_query_string(query_string)
    return @scope if query_string.blank?

    filters = {}

    query_string.scan(
      /(?<key_prefix>[-=])?(?<key>[\w-]+):(?<value>[^\s]+)/,
    ) do |key_prefix, key, value|
      key = FILTER_ALIASES[key] || key

      filters[key] ||= {}
      filters[key]["key_prefixes"] ||= []
      filters[key]["key_prefixes"] << key_prefix
      filters[key]["values"] ||= []
      filters[key]["values"] << value
    end

    filters.each do |filter, hash|
      key_prefixes = hash["key_prefixes"]
      values = hash["values"]

      case filter
      when "category"
        filter_categories(values: key_prefixes.zip(values))
      when "created-by"
        filter_created_by_user(usernames: values.flat_map { |value| value.split(",") })
      when "in"
        filter_in(values: values)
      when "status"
        values.each { |status| @scope = filter_status(status: status) }
      when "tags"
        filter_tags(values: key_prefixes.zip(values))
      end
    end

    @scope
  end

  def filter_status(status:, category_id: nil)
    case status
    when "open"
      @scope = @scope.where("NOT topics.closed AND NOT topics.archived")
    when "closed"
      @scope = @scope.where("topics.closed")
    when "archived"
      @scope = @scope.where("topics.archived")
    when "listed"
      @scope = @scope.where("topics.visible")
    when "unlisted"
      @scope = @scope.where("NOT topics.visible")
    when "deleted"
      category = category_id.present? ? Category.find_by(id: category_id) : nil

      if @guardian.can_see_deleted_topics?(category)
        @scope = @scope.unscope(where: :deleted_at).where("topics.deleted_at IS NOT NULL")
      end
    when "public"
      @scope = @scope.joins(:category).where("NOT categories.read_restricted")
    end

    @scope
  end

  private

  def filter_categories(values:)
    exclude_subcategories_category_slugs = []
    include_subcategories_category_slugs = []

    values.each do |key_prefix, value|
      break if key_prefix && key_prefix != "="

      value
        .scan(
          /^(?<category_slugs>([a-zA-Z0-9\-:]+)(?<delimiter>[,])?([a-zA-Z0-9\-:]+)?(\k<delimiter>[a-zA-Z0-9\-:]+)*)$/,
        )
        .each do |category_slugs, delimiter|
          (
            if key_prefix.presence
              exclude_subcategories_category_slugs
            else
              include_subcategories_category_slugs
            end
          ).concat(category_slugs.split(delimiter))
        end
    end

    category_ids = []

    if exclude_subcategories_category_slugs.present?
      category_ids =
        get_category_ids_from_slugs(
          exclude_subcategories_category_slugs,
          exclude_subcategories: true,
        )
    end

    if include_subcategories_category_slugs.present?
      category_ids.concat(
        get_category_ids_from_slugs(
          include_subcategories_category_slugs,
          exclude_subcategories: false,
        ),
      )
    end

    if category_ids.present?
      @scope = @scope.where("topics.category_id IN (?)", category_ids)
    elsif exclude_subcategories_category_slugs.present? ||
          include_subcategories_category_slugs.present?
      @scope = @scope.none
    end
  end

  def filter_created_by_user(usernames:)
    @scope =
      @scope.joins(:user).where(
        "users.username_lower IN (:usernames)",
        usernames: usernames.map(&:downcase),
      )
  end

  def filter_in(values:)
    values.uniq!

    if values.delete("pinned")
      @scope =
        @scope.where(
          "topics.pinned_at IS NOT NULL AND topics.pinned_until > topics.pinned_at AND ? < topics.pinned_until",
          Time.zone.now,
        )
    end

    if @guardian.user
      if values.delete("bookmarked")
        @scope =
          @scope.joins(:topic_users).where(
            "topic_users.bookmarked AND topic_users.user_id = ?",
            @guardian.user.id,
          )
      end

      if values.present?
        values.each do |value|
          value
            .split(",")
            .each do |topic_notification_level|
              if level = TopicUser.notification_levels[topic_notification_level.to_sym]
                @topic_notification_levels << level
              end
            end
        end

        @scope =
          @scope.joins(:topic_users).where(
            "topic_users.notification_level IN (:topic_notification_levels) AND topic_users.user_id = :user_id",
            topic_notification_levels: @topic_notification_levels.to_a,
            user_id: @guardian.user.id,
          )
      end
    elsif values.present?
      @scope = @scope.none
    end
  end

  def get_category_ids_from_slugs(slugs, exclude_subcategories: false)
    category_ids = Category.ids_from_slugs(slugs)

    category_ids =
      Category
        .where(id: category_ids)
        .filter { |category| @guardian.can_see_category?(category) }
        .map(&:id)

    if !exclude_subcategories
      category_ids = category_ids.flat_map { |category_id| Category.subcategory_ids(category_id) }
    end

    category_ids
  end

  # Accepts an array of tag names and returns an array of tag ids and the tag ids of aliases for the tag names which the user can see.
  # If a block is given, it will be called with the tag ids and alias tag ids as arguments.
  def tag_ids_from_tag_names(tag_names)
    tag_ids, alias_tag_ids =
      DiscourseTagging
        .filter_visible(Tag, @guardian)
        .where_name(tag_names)
        .pluck(:id, :target_tag_id)

    tag_ids ||= []
    alias_tag_ids ||= []

    yield(tag_ids, alias_tag_ids) if block_given?

    all_tag_ids = tag_ids.concat(alias_tag_ids)
    all_tag_ids.compact!
    all_tag_ids.uniq!
    all_tag_ids
  end

  def filter_tags(values:)
    return if !SiteSetting.tagging_enabled?

    exclude_all_tags = []
    exclude_any_tags = []
    include_any_tags = []
    include_all_tags = []

    values.each do |key_prefix, value|
      break if key_prefix && key_prefix != "-"

      value.scan(
        /^(?<tag_names>([a-zA-Z0-9\-]+)(?<delimiter>[,+])?([a-zA-Z0-9\-]+)?(\k<delimiter>[a-zA-Z0-9\-]+)*)$/,
      ) do |tag_names, delimiter|
        match_all =
          if delimiter == ","
            false
          else
            true
          end

        (
          case [key_prefix, match_all]
          in ["-", true]
            exclude_all_tags
          in ["-", false]
            exclude_any_tags
          in [nil, true]
            include_all_tags
          in [nil, false]
            include_any_tags
          end
        ).concat(tag_names.split(delimiter))
      end
    end

    if exclude_all_tags.present?
      exclude_topics_with_all_tags(tag_ids_from_tag_names(exclude_all_tags))
    end

    if exclude_any_tags.present?
      exclude_topics_with_any_tags(tag_ids_from_tag_names(exclude_any_tags))
    end

    if include_any_tags.present?
      include_topics_with_any_tags(tag_ids_from_tag_names(include_any_tags))
    end

    if include_all_tags.present?
      has_invalid_tags = false

      all_tag_ids =
        tag_ids_from_tag_names(include_all_tags) do |tag_ids, _|
          has_invalid_tags = tag_ids.length < include_all_tags.length
        end

      if has_invalid_tags
        @scope = @scope.none
      else
        include_topics_with_all_tags(all_tag_ids)
      end
    end
  end

  def topic_tags_alias
    @topic_tags_alias ||= 0
    "tt#{@topic_tags_alias += 1}"
  end

  def exclude_topics_with_all_tags(tag_ids)
    where_clause = []

    tag_ids.each do |tag_id|
      sql_alias = "tt#{topic_tags_alias}"

      @scope =
        @scope.joins(
          "LEFT JOIN topic_tags #{sql_alias} ON #{sql_alias}.topic_id = topics.id AND #{sql_alias}.tag_id = #{tag_id}",
        )

      where_clause << "#{sql_alias}.topic_id IS NULL"
    end

    @scope = @scope.where(where_clause.join(" OR "))
  end

  def exclude_topics_with_any_tags(tag_ids)
    @scope =
      @scope.where(
        "topics.id NOT IN (SELECT DISTINCT topic_id FROM topic_tags WHERE topic_tags.tag_id IN (?))",
        tag_ids,
      )
  end

  def include_topics_with_all_tags(tag_ids)
    tag_ids.each do |tag_id|
      sql_alias = "tt#{topic_tags_alias}"

      @scope =
        @scope.joins(
          "INNER JOIN topic_tags #{sql_alias} ON #{sql_alias}.topic_id = topics.id AND #{sql_alias}.tag_id = #{tag_id}",
        )
    end
  end

  def include_topics_with_any_tags(tag_ids)
    @scope = @scope.joins(:topic_tags).where("topic_tags.tag_id IN (?)", tag_ids).distinct(:id)
  end
end
