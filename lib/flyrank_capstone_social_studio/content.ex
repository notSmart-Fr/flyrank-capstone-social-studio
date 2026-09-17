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
    from(v in Variant, where: v.post_id == ^post_id)
    |> Repo.all()
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
  Ingests a post (from raw text/markdown or an external web URL) and generates
  initial platform draft variants atomically inside a database transaction.

  If `source_type` is set to `"url"`, the web page content is fetched and extracted
  over HTTP *before* opening the DB transaction to prevent pool starvation.
  """
 def ingest_and_generate(post_attrs, platforms \\ ["telegram", "mock_x", "mock_linkedin"]) do
  with {:ok, resolved_attrs} <- resolve_post_attrs(post_attrs) do
    # 1. Compute deterministic hash from resolved parameters
    title = resolved_attrs["title"] || ""
    content = resolved_attrs["content"] || ""
    hash = :crypto.hash(:sha256, "#{title}:#{content}") |> Base.encode16()

    # 2. Check for duplicate within 5 minutes window
    cutoff = DateTime.utc_now() |> DateTime.add(-300, :second)

    existing_post =
      from(p in Post,
        where: p.content_hash == ^hash and p.inserted_at >= ^cutoff,
        limit: 1
      )
      |> Repo.one()

    if existing_post do
      # Short-circuit: Return existing post and variants without regenerating
      variants = Repo.all(from v in Variant, where: v.post_id == ^existing_post.id)
      {:ok, {existing_post, variants}}
    else
      # 3. New submission: Proceed with transaction
      Repo.transaction(fn ->
        # Pass content_hash into creation attributes
        attrs_with_hash = Map.put(resolved_attrs, "content_hash", hash)

        case create_post(attrs_with_hash) do
          {:ok, post} ->
            variants =
              platforms
              |> Enum.map(fn platform ->
                case generate_variant_for_platform(post, platform) do
                  {:ok, ab_variants} -> ab_variants
                  {:error, reason_or_changeset} -> Repo.rollback(reason_or_changeset)
                end
              end)
              |> List.flatten()

            # Sum generation costs
            total_cost =
              Enum.reduce(variants, Decimal.new("0.0"), fn v, acc ->
                cost = v.generation_cost || Decimal.new("0.0")
                Decimal.add(acc, cost)
              end)

            # Update parent Post with aggregated AI costs
            case update_post(post, %{total_ai_cost: total_cost}) do
              {:ok, updated_post} ->
                {updated_post, variants}

              {:error, changeset} ->
                Repo.rollback(changeset)
            end

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end
  end
end
  @doc """
Generates both Variant A and Variant B drafts for a given platform.
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
            {:ok, [var_a, var_b]}
          end

        {:error, reason} ->
          {:error, reason}
      end
  end
end

# Private helper to parse GroundingVerifier results
defp determine_grounding_status({:ok, :grounded}), do: {"draft", nil}
defp determine_grounding_status({:error, :hallucination_detected, claims}) do
  {"rejected", "Grounding Audit Failed: Fake or unsupported claims detected -> #{Enum.join(claims, ", ")}"}
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

  # Fetches HTML content from URL outside the DB transaction if source_type == "url"
  defp resolve_post_attrs(%{"source_type" => "url", "url" => url} = attrs) when is_binary(url) do
    case UrlFetcher.fetch_and_extract(url) do
      {:ok, extracted_text} ->
        updated_attrs =
          attrs
          |> Map.put("content", extracted_text)
          |> Map.put_new("title", "Fetched: #{url}")

        {:ok, updated_attrs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_post_attrs(attrs), do: {:ok, attrs}

end
