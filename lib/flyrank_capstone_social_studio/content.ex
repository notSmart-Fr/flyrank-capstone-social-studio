defmodule FlyrankCapstoneSocialStudio.Content do
  @moduledoc """
  The Content context managing blog posts, URL content fetching,
  platform variant generation, idempotency locks, and reviewer workflows.
  equenceDiagram
    autonumber
    actor User as User / Client API
    participant Content as Content Context
    participant Repo as PostgreSQL (Ecto)
    participant Oban as Oban Worker
    participant Gemini as Gemini LLM API
    participant Audit as GroundingVerifier

    box Ingestion Phase
    User->>Content: ingest_and_template(attrs, platforms, idempotency_key)
    alt Key processing or completed?
        Content->>Repo: Check IdempotencyKey
        Repo-->>Content: Return cached payload or in-flight error
        Content-->>User: {:ok, cached} OR {:error, :concurrent_request_in_flight}
    else Key is new
        Content->>Repo: Insert IdempotencyKey ("processing")
        Content->>Repo: Save %Post{} & Initial Local Draft %Variant{}s
        Content->>Repo: Update IdempotencyKey ("completed")
        Content-->>User: {:ok, {post, local_variants}}
    end
    end

    box Asynchronous AI Generation Phase
    User->>Content: queue_ai_variant_generation(post_id, platform)
    Content->>Oban: Enqueue GenerateVariantsWorker
    Oban->>Gemini: POST /generateContent (Generate A/B Variants)
    Gemini-->>Oban: 200 OK (A/B JSON + usageMetadata)
    Oban->>Repo: Log AiGeneration telemetry & update Post.total_ai_cost
    end

    box Grounding Audit Phase
    Oban->>Audit: verify_grounding(post.content, generated_variant)
    Audit->>Gemini: POST /generateContent (Source vs Variant Audit)

    alt Factual claims supported
        Gemini-->>Audit: {"is_grounded": true}
        Audit-->>Oban: {:ok, :grounded}
        Oban->>Repo: Save %Variant{status: "draft"}
    else Hallucination / Fake stats detected
        Gemini-->>Audit: {"is_grounded": false, "unsupported_claims": [...]}
        Audit-->>Oban: {:error, :hallucination_detected, claims}
        Oban->>Repo: Save %Variant{status: "rejected", rejection_reason: "..."}
    else Network / Audit API Error
        Gemini-->>Audit: HTTP 500 / Timeout
        Audit-->>Oban: {:error, :audit_failed, reason}
        Oban->>Repo: Save %Variant{status: "needs_review", rejection_reason: "..."}
    end
    end
  """

  import Ecto.Query, warn: false
  alias FlyrankCapstoneSocialStudio.Content.ConstraintProfile
  alias FlyrankCapstoneSocialStudio.Content.IdempotencyKey
  alias FlyrankCapstoneSocialStudio.Content.Post
  alias FlyrankCapstoneSocialStudio.Content.UrlFetcher
  alias FlyrankCapstoneSocialStudio.Content.Variant
  alias FlyrankCapstoneSocialStudio.Publishing.{PublishAttempt, Slot}
  alias FlyrankCapstoneSocialStudio.Repo

  # ===========================================================================
  # Post CRUD Operations
  # ===========================================================================

  @doc """
  Returns the list of all posts.
  """
  @spec list_posts() :: list(Post.t())
  def list_posts, do: Repo.all(Post)

  @doc """
  Gets a single post by ID.

  Raises `Ecto.NoResultsError` if the Post does not exist.
  """
  @spec get_post!(term()) :: Post.t()
  def get_post!(id), do: Repo.get!(Post, id)

  @doc """
  Creates a new post.
  """
  @spec create_post(map()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def create_post(attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing post.
  """
  @spec update_post(Post.t(), map()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Post and cleans up all associated child records (publish attempts,
  slots, and variants) atomically in a single transaction.
  """
  @spec delete_post(Post.t()) :: {:ok, Post.t()} | {:error, term()}
  def delete_post(%Post{} = post) do
    # Select IDs into clean subqueries to avoid opaque Multi schema joins
    variants_query = from(v in Variant, where: v.post_id == ^post.id)

    slots_query =
      from(s in Slot,
        where:
          s.variant_id in subquery(from(v in Variant, where: v.post_id == ^post.id, select: v.id))
      )

    publish_attempts_query =
      from(pa in PublishAttempt, where: pa.slot_id in subquery(slots_query |> select([s], s.id)))

    Repo.transaction(fn ->
      Repo.delete_all(publish_attempts_query)
      Repo.delete_all(slots_query)
      Repo.delete_all(variants_query)

      case Repo.delete(post) do
        {:ok, deleted_post} -> deleted_post
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, deleted_post} -> {:ok, deleted_post}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec change_post(FlyrankCapstoneSocialStudio.Content.Post.t()) :: Ecto.Changeset.t()
  @doc """
  Returns an `%Ecto.Changeset{}` for tracking post changes.
  """
  @spec change_post(Post.t(), map()) :: Ecto.Changeset.t()
  def change_post(%Post{} = post, attrs \\ %{}) do
    Post.changeset(post, attrs)
  end

  # ===========================================================================
  # Variant CRUD Operations
  # ===========================================================================

  @doc """
  Returns the list of all variants.
  """
  @spec list_variants() :: list(Variant.t())
  def list_variants, do: Repo.all(Variant)

  @doc """
  Gets a single variant by ID.

  Raises `Ecto.NoResultsError` if the Variant does not exist.
  """
  @spec get_variant!(term()) :: Variant.t()
  def get_variant!(id), do: Repo.get!(Variant, id)

  @doc """
  Retrieves all variants belonging to a specific post ID.
  """
  @spec get_post_variants(term()) :: list(Variant.t())
  def get_post_variants(post_id) do
    list_variants_for_post(post_id)
  end

  @doc """
  Creates a new variant.
  """
  @spec create_variant(map()) :: {:ok, Variant.t()} | {:error, Ecto.Changeset.t()}
  def create_variant(attrs \\ %{}) do
    %Variant{}
    |> Variant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing variant.
  """
  @spec update_variant(Variant.t(), map()) :: {:ok, Variant.t()} | {:error, Ecto.Changeset.t()}
  def update_variant(%Variant{} = variant, attrs) do
    variant
    |> Variant.changeset(attrs)
    |> Repo.update()
  end

  # ===========================================================================
  # Idempotent Ingestion & Templating
  # ===========================================================================

  @doc """
  Ingests raw content or an external URL, constructs a base `%Post{}`, and generates
  local draft variants for specified platforms without external AI calls.

  Guaranteed idempotent via the `idempotency_key` parameter.

  ## Behavior:
  1. Returns cached `{post, variants}` if the idempotency key was previously completed.
  2. Returns `{:error, :concurrent_request_in_flight}` if the key is currently processing.
  3. Executes HTTP URL extraction **outside** the database transaction to prevent pool starvation.
  4. Atomically commits the idempotency record, post, and variants inside a single transaction.
  """
  @spec ingest_and_template(map(), list(String.t()), String.t() | nil) ::
          {:ok, {Post.t(), list(Variant.t())}} | {:error, term()}
  def ingest_and_template(
        post_attrs,
        platforms \\ ["telegram", "mock_x", "mock_linkedin"],
        idempotency_key \\ nil
      ) do
    key = idempotency_key || Ecto.UUID.generate()

    case Repo.get_by(IdempotencyKey, key: key) do
      # 1. Previously completed -> Return cached response
      %IdempotencyKey{status: "completed", response_payload: payload} ->
        {:ok, deserialize_response(payload)}

      # 2. Currently processing in another process -> In-flight error
      %IdempotencyKey{status: "processing"} ->
        {:error, :concurrent_request_in_flight}

      # 3. New key attempt -> Resolve URL outside DB transaction, then run transaction
      nil ->
        with {:ok, resolved_attrs} <- resolve_post_attrs(post_attrs) do
          execute_idempotent_ingestion(key, resolved_attrs, platforms)
        end
    end
  end

  # Executes the DB transaction for locking key and saving Post + Variants
  defp execute_idempotent_ingestion(key, resolved_attrs, platforms) do
    case Repo.transaction(fn -> run_ingestion_transaction(key, resolved_attrs, platforms) end) do
      {:ok, {post, variants}} ->
        {:ok, {post, variants}}

      {:error, {:idempotency_key_conflict, _changeset}} ->
        {:error, :concurrent_request_in_flight}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_ingestion_transaction(key, resolved_attrs, platforms) do
    lock_changeset = IdempotencyKey.changeset(%{key: key, status: "processing"})

    with {:ok, _key_record} <- Repo.insert(lock_changeset),
         {:ok, {post, variants}} <- execute_template_ingest_transaction(resolved_attrs, platforms),
         payload = serialize_response(post, variants),
         {:ok, _updated_key} <- update_idempotency_status(key, "completed", payload) do
      {post, variants}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        handle_ingestion_error(changeset)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp handle_ingestion_error(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :key) do
      Repo.rollback({:idempotency_key_conflict, changeset})
    else
      Repo.rollback(changeset)
    end
  end

  defp update_idempotency_status(key, status, payload) do
    case Repo.get_by(IdempotencyKey, key: key) do
      nil ->
        {:error, :key_not_found}

      record ->
        record
        |> IdempotencyKey.changeset(%{status: status, response_payload: payload})
        |> Repo.update()
    end
  end

  @doc """
  Generates a local, rule-based template draft variant for a given platform
  using its defined `ConstraintProfile` rules (character limits, tone, hashtags).
  """
  @spec create_template_variant_for_platform(Post.t(), String.t()) ::
          {:ok, Variant.t()} | {:error, term()}
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

  # ===========================================================================
  # State Machine & Review Workflows
  # ===========================================================================

  @doc """
  Approves a variant for scheduling and publication.
  """
  @spec approve_variant(Variant.t()) :: {:ok, Variant.t()} | {:error, Ecto.Changeset.t()}
  def approve_variant(%Variant{} = variant) do
    variant
    |> Variant.changeset(%{status: "approved"})
    |> Repo.update()
  end

  @doc """
  Rejects a variant with an optional reviewer note/reason.
  """
  @spec reject_variant(Variant.t(), String.t()) ::
          {:ok, Variant.t()} | {:error, Ecto.Changeset.t()}
  def reject_variant(%Variant{} = variant, reason \\ "Content rejected by reviewer") do
    variant
    |> Variant.changeset(%{status: "rejected", rejection_reason: reason})
    |> Repo.update()
  end

  @doc """
  Audits a variant's factual grounding against its parent post.
  Updates the variant's status and rejection reason accordingly.
  """
  @spec verify_variant_grounding(Variant.t(), keyword()) ::
          {:ok, Variant.t()} | {:error, Ecto.Changeset.t()}
  def verify_variant_grounding(%Variant{} = variant, opts \\ []) do
    post = get_post!(variant.post_id)

    case FlyrankCapstoneSocialStudio.Content.GroundingVerifier.verify_grounding(
           post.content,
           variant.content,
           opts
         ) do
      {:ok, :grounded} ->
        update_variant(variant, %{status: "draft", rejection_reason: nil})

      {:error, :hallucination_detected, claims} ->
        reason =
          "Grounding Audit Failed: Fake or unsupported claims detected -> #{Enum.join(claims, ", ")}"

        update_variant(variant, %{status: "rejected", rejection_reason: reason})

      {:error, :audit_failed, reason} ->
        update_variant(variant, %{
          status: "needs_review",
          rejection_reason: "Grounding Audit Incomplete: #{reason}"
        })
    end
  end

  @doc """
  Retrieves a blog post with all its associated variants and scheduled publishing slots.
  """
  @spec get_campaign_details(term()) :: Post.t() | nil
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

  # Persists the post and iterates over platform targets to create draft variants
  defp execute_template_ingest_transaction(resolved_attrs, platforms) do
    case create_post(resolved_attrs) do
      {:ok, post} ->
        variants = create_template_variants(post, platforms)
        {:ok, {post, variants}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp create_template_variants(post, platforms) do
    Enum.map(platforms, fn platform ->
      case create_template_variant_for_platform(post, platform) do
        {:ok, variant} -> variant
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Formats content based on profile rules (hashtags, character limits)
  defp build_template_content(
         %Post{title: title, content: content},
         %ConstraintProfile{} = profile
       ) do
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

  defp list_variants_for_post(post_id) do
    from(v in Variant, where: v.post_id == ^post_id)
    |> Repo.all()
  end

  # Fetches HTML content over HTTP *before* opening the DB transaction
  defp resolve_post_attrs(%{"source_type" => "url"} = attrs) do
    url = Map.get(attrs, "url") || Map.get(attrs, "content")

    case url do
      url when is_binary(url) and url != "" ->
        resolve_url_post_attrs(attrs, url)

      _ ->
        {:ok, attrs}
    end
  end

  defp resolve_post_attrs(attrs), do: {:ok, attrs}

  defp resolve_url_post_attrs(attrs, url) do
    with {:ok, extracted_text} <- UrlFetcher.fetch_and_extract(url) do
      updated_attrs =
        attrs
        |> Map.put("url", url)
        |> Map.put("content", extracted_text)
        |> Map.update("title", "Fetched: #{url}", fn
          "" -> "Fetched: #{url}"
          existing -> existing
        end)

      {:ok, updated_attrs}
    end
  end

  # Serialization helpers so cached JSON maps reconstruct %Post{} & %Variant{} structs
  defp serialize_response(post, variants) do
    %{
      "data" => %{
        "id" => post.id,
        "title" => post.title,
        "content" => post.content,
        "source_type" => post.source_type,
        "url" => post.url,
        "external_source_id" => post.external_source_id,
        "inserted_at" => NaiveDateTime.to_iso8601(post.inserted_at),
        "variants" =>
          Enum.map(variants, fn v ->
            %{
              "id" => v.id,
              "post_id" => v.post_id,
              "platform" => v.platform,
              "status" => v.status,
              "content" => v.content,
              "character_count" => v.character_count,
              "hashtags_count" => v.hashtags_count
            }
          end)
      }
    }
  end

  defp deserialize_response(%{
         "data" => %{
           "id" => id,
           "title" => title,
           "content" => content,
           "source_type" => source_type,
           "url" => url,
           "external_source_id" => external_source_id,
           "inserted_at" => inserted_at_raw,
           "variants" => variants_maps
         }
       }) do
    post = %Post{
      id: id,
      title: title,
      content: content,
      source_type: source_type,
      url: url,
      external_source_id: external_source_id,
      inserted_at: parse_datetime(inserted_at_raw)
    }

    variants =
      Enum.map(
        variants_maps,
        &struct(FlyrankCapstoneSocialStudio.Content.Variant, symbolize_keys(&1))
      )

    {post, variants}
  end

  defp symbolize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp parse_datetime(%NaiveDateTime{} = dt), do: dt
  defp parse_datetime(%DateTime{} = dt), do: DateTime.to_naive(dt)

  defp parse_datetime(dt_str) when is_binary(dt_str) do
    case NaiveDateTime.from_iso8601(dt_str) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
