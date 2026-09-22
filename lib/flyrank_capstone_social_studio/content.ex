defmodule FlyrankCapstoneSocialStudio.Content do
  @moduledoc """
  The Content context managing blog posts, URL content fetching,
  platform variant generation, and reviewer workflows.
  """

  import Ecto.Query, warn: false
  alias FlyrankCapstoneSocialStudio.Content.AiGenerator
  alias FlyrankCapstoneSocialStudio.Content.ConstraintProfile
  alias FlyrankCapstoneSocialStudio.Content.GroundingVerifier
  alias FlyrankCapstoneSocialStudio.Content.Post
  alias FlyrankCapstoneSocialStudio.Content.UrlFetcher
  alias FlyrankCapstoneSocialStudio.Content.Variant
  alias FlyrankCapstoneSocialStudio.Repo

  # ===========================================================================
  # Post CRUD Operations
  # ===========================================================================

  @doc """
  Returns the list of all posts.
  """
  def list_posts, do: Repo.all(Post)

  @doc """
  Gets a single post by ID. Raises `Ecto.NoResultsError` if not found.
  """
  def get_post!(id), do: Repo.get!(Post, id)

  @doc """
  Creates a new post.
  """
  def create_post(attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing post.
  """
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a post.
  """
  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post changes.
  """
  def change_post(%Post{} = post, attrs \\ %{}) do
    Post.changeset(post, attrs)
  end

  # ===========================================================================
  # Variant CRUD Operations
  # ===========================================================================

  @doc """
  Returns the list of all variants.
  """
  def list_variants, do: Repo.all(Variant)

  @doc """
  Gets a single variant by ID. Raises `Ecto.NoResultsError` if not found.
  """
  def get_variant!(id), do: Repo.get!(Variant, id)

  @doc """
  Retrieves all variants belonging to a specific post ID.
  """
  def get_post_variants(post_id) do
    list_variants_for_post(post_id)
  end

  @doc """
  Creates a new variant.
  """
  def create_variant(attrs \\ %{}) do
    %Variant{}
    |> Variant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing variant.
  """
  def update_variant(%Variant{} = variant, attrs) do
    variant
    |> Variant.changeset(attrs)
    |> Repo.update()
  end

# ===========================================================================
  # Ingestion & Variant Generation Pipeline
  # ===========================================================================

  @doc """
  Ingests a post (from raw text/markdown or an external web URL) and constructs
  initial platform draft variants locally using `ConstraintProfile` definitions
  without making external AI API calls.

  If `source_type` is set to `"url"`, the web page content is fetched and extracted
  over HTTP *before* opening the DB transaction to prevent pool starvation.
  """
  def ingest_and_template(post_attrs, platforms \\ ["telegram", "mock_x", "mock_linkedin"]) do
    with {:ok, resolved_attrs} <- resolve_post_attrs(post_attrs) do
      # 1. Compute deterministic hash from resolved parameters
      title = resolved_attrs["title"] || ""
      content = resolved_attrs["content"] || ""
      hash = :crypto.hash(:sha256, "#{title}:#{content}") |> Base.encode16()

      # 2. Check for duplicate within 5 minutes lookback window via private helper
      case get_recent_post_by_hash(hash, 300) do
        %Post{} = existing_post ->
          # Short-circuit: Return existing post and variants without regenerating
          {:ok, {existing_post, list_variants_for_post(existing_post.id)}}

        nil ->
          # 3. New submission: Proceed with local template ingestion transaction
          execute_template_ingest_transaction(resolved_attrs, hash, platforms)
      end
    end
  end

  @doc """
  Generates a local, rule-based template draft variant for a given platform
  using its defined `ConstraintProfile` rules (character limits, tone, hashtags)
  without calling Gemini.
  """
  def create_template_variant_for_platform(%Post{} = post, platform) do
    case ConstraintProfile.get(platform) do
      nil ->
        {:error, :unsupported_platform}

      profile ->
        formatted_content = build_template_content(post, profile)

        create_variant(%{
          post_id: post.id,
          platform: platform,
          content: formatted_content,
          status: "draft",
          model_used: "Local Constraint Template"
        })
    end
  end

  @doc """
  Triggered explicitly on-demand to generate both Variant A and Variant B drafts
  for a given platform using Gemini Flash.

  Executes grounding verification checks against the source post content and records
  token usage and AI generation costs upon completion.
  """
  def generate_variant_for_platform(%Post{} = post, platform) do
    case ConstraintProfile.get(platform) do
      nil ->
        {:error, :unsupported_platform}

      profile ->
        case AiGenerator.generate_ab_variants(post.content, platform, profile) do
          {:ok, result} ->
            # 1. Run Grounding Verification on both generated variants
            ground_a = GroundingVerifier.verify_grounding(post.content, result.variant_a)
            ground_b = GroundingVerifier.verify_grounding(post.content, result.variant_b)

            # 2. Determine status and rejection reasons based on grounding results
            {status_a, reason_a} = determine_grounding_status(ground_a)
            {status_b, reason_b} = determine_grounding_status(ground_b)

            # Halve token counts/cost per variant for split attribution
            half_cost = Decimal.div(result.cost, 2)
            half_prompt = div(result.prompt_tokens, 2)
            half_completion = div(result.completion_tokens, 2)

            # 3. Create variants with dynamic status ("draft" or "rejected")
            with {:ok, var_a} <- create_variant(%{
                   post_id: post.id,
                   platform: platform,
                   content: result.variant_a,
                   variant_label: "A",
                   status: status_a,
                   rejection_reason: reason_a,
                   prompt_tokens: half_prompt,
                   completion_tokens: half_completion,
                   total_tokens: half_prompt + half_completion,
                   generation_cost: half_cost,
                   model_used: result.model
                 }),
                 {:ok, var_b} <- create_variant(%{
                   post_id: post.id,
                   platform: platform,
                   content: result.variant_b,
                   variant_label: "B",
                   status: status_b,
                   rejection_reason: reason_b,
                   prompt_tokens: half_prompt,
                   completion_tokens: half_completion,
                   total_tokens: half_prompt + half_completion,
                   generation_cost: half_cost,
                   model_used: result.model
                 }) do
              # Recalculate parent post aggregated AI cost
              update_post_total_ai_cost(post.id)
              {:ok, [var_a, var_b]}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # ===========================================================================
  # State Machine & Review Workflows
  # ===========================================================================

  @doc """
  Approves a variant for scheduling and publication.
  """
  def approve_variant(%Variant{} = variant) do
    variant
    |> Variant.changeset(%{status: "approved"})
    |> Repo.update()
  end

  @doc """
  Rejects a variant with an optional reviewer note/reason.
  """
  def reject_variant(%Variant{} = variant, reason \\ "Content rejected by reviewer") do
    variant
    |> Variant.changeset(%{status: "rejected", rejection_reason: reason})
    |> Repo.update()
  end

  @doc """
  Retrieves a blog post with all its associated variants and scheduled publishing slots.
  """
  def get_campaign_details(post_id) do
    from(p in Post,
      where: p.id == ^post_id,
      preload: [variants: :slots]
    )
    |> Repo.one()
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Executes post creation and local template variant generation inside a DB transaction
  defp execute_template_ingest_transaction(resolved_attrs, hash, platforms) do
    Repo.transaction(fn ->
      attrs_with_hash = Map.put(resolved_attrs, "content_hash", hash)

      case create_post(attrs_with_hash) do
        {:ok, post} ->
          variants =
            platforms
            |> Enum.map(fn platform ->
              case create_template_variant_for_platform(post, platform) do
                {:ok, variant} -> variant
                {:error, reason} -> Repo.rollback(reason)
              end
            end)

          {post, variants}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Local rule-based draft generator respecting platform constraints dynamically
  defp build_template_content(%Post{title: title, content: content}, %ConstraintProfile{} = profile) do
    # Generate allowed number of hashtags dynamically based on profile limit
    tags =
      case profile.max_hashtags do
        0 -> ""
        1 -> "\n\n#tech"
        _ -> "\n\n#tech #update"
      end

    max_body_len = max(0, profile.max_length - (String.length(title) + String.length(tags) + 10))
    snippet = String.slice(content || "", 0, max_body_len)

    "📌 #{title}\n\n#{snippet}#{tags}"
    |> String.slice(0, profile.max_length)
  end

  # Recalculates aggregated total AI cost on the parent post
  defp update_post_total_ai_cost(post_id) do
    post = get_post!(post_id)
    variants = list_variants_for_post(post_id)

    total_cost =
      Enum.reduce(variants, Decimal.new("0.0"), fn v, acc ->
        cost = v.generation_cost || Decimal.new("0.0")
        Decimal.add(acc, cost)
      end)

    update_post(post, %{total_ai_cost: total_cost})
  end

  # Fetches a post created within lookback_seconds matching the content hash
  defp get_recent_post_by_hash(hash, lookback_seconds) do
    cutoff = DateTime.utc_now() |> DateTime.add(-lookback_seconds, :second)

    from(p in Post,
      where: p.content_hash == ^hash and p.inserted_at >= ^cutoff,
      limit: 1
    )
    |> Repo.one()
  end

  # Fetches all variants associated with a post ID
  defp list_variants_for_post(post_id) do
    from(v in Variant, where: v.post_id == ^post_id)
    |> Repo.all()
  end

  # Parses GroundingVerifier results into status and rejection reason tuples
  defp determine_grounding_status({:ok, :grounded}), do: {"draft", nil}

  defp determine_grounding_status({:error, :hallucination_detected, claims}) do
    {"rejected", "Grounding Audit Failed: Fake or unsupported claims detected -> #{Enum.join(claims, ", ")}"}
  end

  # Fetches HTML content from URL outside the DB transaction if source_type == "url"
  defp resolve_post_attrs(%{"source_type" => "url"} = attrs) do
    url = Map.get(attrs, "url") || Map.get(attrs, "content")

    case url do
      url when is_binary(url) and url != "" ->
        case UrlFetcher.fetch_and_extract(url) do
          {:ok, extracted_text} ->
            updated_attrs =
              attrs
              |> Map.put("url", url)
              |> Map.put("content", extracted_text)
              |> Map.update("title", "Fetched: #{url}", fn
                "" -> "Fetched: #{url}"
                existing -> existing
              end)

            {:ok, updated_attrs}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:ok, attrs}
    end
  end

  defp resolve_post_attrs(attrs), do: {:ok, attrs}
end
