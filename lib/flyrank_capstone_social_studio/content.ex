defmodule FlyrankCapstoneSocialStudio.Content do
  @moduledoc """
  The Content context managing blog posts, URL content fetching,
  platform variant generation, and reviewer workflows.
  """

  import Ecto.Query, warn: false
  alias FlyrankCapstoneSocialStudio.Repo

  alias FlyrankCapstoneSocialStudio.Content.Post
  alias FlyrankCapstoneSocialStudio.Content.Variant
  alias FlyrankCapstoneSocialStudio.Content.ConstraintProfile
  alias FlyrankCapstoneSocialStudio.Content.UrlFetcher

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
      Repo.transaction(fn ->
        case create_post(resolved_attrs) do
          {:ok, post} ->
            variants =
              Enum.map(platforms, fn platform ->
                case generate_variant_for_platform(post, platform) do
                  {:ok, variant} -> variant
                  {:error, reason_or_changeset} -> Repo.rollback(reason_or_changeset)
                end
              end)

            {post, variants}

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc """
  Generates a variant content draft tailored to a platform's constraint profile.
  """
  def generate_variant_for_platform(%Post{} = post, platform) do
    case ConstraintProfile.get(platform) do
      nil ->
        {:error, :unsupported_platform}

      profile ->
        generated_text = draft_text_for_platform(post.content, profile)

        create_variant(%{
          post_id: post.id,
          platform: platform,
          content: generated_text,
          status: "draft"
        })
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

  # Deterministic heuristic generator based on platform length and hashtag limits
  defp draft_text_for_platform(content, profile) do
    max_text_len = max(profile.max_length - 20, 1)
    trimmed_content = String.slice(content, 0, max_text_len)

    hashtags =
      case profile.max_hashtags do
        1 -> " #tech"
        2 -> " #tech #news"
        _ -> " #tech #news #update"
      end

    trimmed_content <> hashtags
  end
end
