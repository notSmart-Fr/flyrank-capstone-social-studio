defmodule FlyrankCapstoneSocialStudioWeb.ContentLive.Index do
  use FlyrankCapstoneSocialStudioWeb, :live_view

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Content.Post

  @impl true
  def mount(_params, _session, socket) do
    posts = Content.list_posts()
    changeset = Content.change_post(%Post{})

    {:ok,
     socket
     |> assign(:page_title, "Social Content Studio")
     |> assign(:posts_count, length(posts))
     |> assign(:source_type, "markdown")
     |> stream(:posts, posts)
     |> assign(:changeset, changeset)
     |> assign(:loading, false)}
  end

  # Event 1: Validates form input on changes/blur & tracks selected source_type
  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    source_type = Map.get(post_params, "source_type", "markdown")

    changeset =
      %Post{}
      |> Content.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:source_type, source_type)
     |> assign(:changeset, changeset)}
  end

  # Event 2: Ingests post & generates AI variants using Content.ingest_and_generate/2
  @impl true
  def handle_event("save_post", %{"post" => post_params} = params, socket) do
    platforms = Map.get(params, "platforms", ["telegram", "mock_x", "mock_linkedin"])
    socket = assign(socket, :loading, true)

    case Content.ingest_and_generate(post_params, platforms) do
      {:ok, {post, _variants}} ->
        changeset = Content.change_post(%Post{})

        {:noreply,
         socket
         |> stream_insert(:posts, post, at: 0)
         |> update(:posts_count, &(&1 + 1))
         |> assign(:changeset, changeset)
         |> assign(:loading, false)
         |> put_flash(:info, "Content ingested and AI variants generated successfully!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> assign(:loading, false)
         |> put_flash(:error, "Validation failed. Please check the form errors below.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Ingestion failed: #{inspect(reason)}")}
    end
  end
end
