defmodule FlyrankCapstoneSocialStudio.Content.Variant do
  use Ecto.Schema
  import Ecto.Changeset

  alias FlyrankCapstoneSocialStudio.Content.ConstraintProfile

  schema "variants" do
    field :content, :string
    field :platform, :string
    field :status, :string, default: "draft"
    field :hashtags_count, :integer
    field :character_count, :integer
    field :rejection_reason, :string
    field :variant_label, :string, virtual: true
    # AI Cost & Token tracking fields
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :total_tokens, :integer
    field :generation_cost, :decimal, default: Decimal.new("0.0")
    field :model_used, :string

    belongs_to :post, FlyrankCapstoneSocialStudio.Content.Post
    has_many :slots, FlyrankCapstoneSocialStudio.Publishing.Slot

    timestamps()
  end

  @doc false
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [
      :post_id,
      :platform,
      :content,
      :status,
      :hashtags_count,
      :character_count,
      :rejection_reason,
      :model_used,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens,
      :generation_cost
    ])
    |> validate_required([:platform, :content, :status])
    |> validate_inclusion(:status, ["draft", "approved", "rejected", "published"])
    |> validate_inclusion(:platform, ConstraintProfile.supported_platforms())
    |> calculate_counts()
    |> validate_constraints()
  end

  defp calculate_counts(changeset) do
    case get_field(changeset, :content) do
      content when is_binary(content) ->
        char_count = String.length(content)
        hashtag_count = ConstraintProfile.count_hashtags(content)

        changeset
        |> put_change(:character_count, char_count)
        |> put_change(:hashtags_count, hashtag_count)

      _ ->
        changeset
    end
  end

  defp validate_constraints(changeset) do
    platform = get_field(changeset, :platform)
    content = get_field(changeset, :content)

    profile = ConstraintProfile.get(platform)

    if profile && is_binary(content) do
      char_count = String.length(content)
      hashtag_count = ConstraintProfile.count_hashtags(content)

      changeset
      |> validate_length(char_count, profile.max_length, platform)
      |> validate_hashtags(hashtag_count, profile.max_hashtags, platform)
      |> validate_tone(content, profile, platform)
    else
      changeset
    end
  end

  defp validate_length(changeset, actual, max, platform) when actual > max do
    add_error(
      changeset,
      :content,
      "exceeds maximum character limit of #{max} for #{platform} (got #{actual})"
    )
  end

  defp validate_length(changeset, _actual, _max, _platform), do: changeset

  defp validate_hashtags(changeset, actual, max, platform) when actual > max do
    add_error(
      changeset,
      :content,
      "exceeds maximum hashtag count of #{max} for #{platform} (got #{actual})"
    )
  end

  defp validate_hashtags(changeset, _actual, _max, _platform), do: changeset

  # Tone validation rules helper
  defp validate_tone(changeset, content, _profile, platform) do
    banned_tone_words = ["OMG", "SLAY", "LMAO"]

    if Enum.any?(banned_tone_words, &String.contains?(content, &1)) do
      add_error(
        changeset,
        :content,
        "violates tone rules for #{platform}"
      )
    else
      changeset
    end
  end
end
