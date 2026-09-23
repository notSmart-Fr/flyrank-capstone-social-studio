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

  @impl true
  def handle_event("delete_post", %{"id" => id}, socket) do
    post = Content.get_post!(id)

    case Content.delete_post(post) do
      {:ok, _deleted_post} ->
        # Calculate new count (or call Content.count_posts())
        new_count = max(0, socket.assigns.posts_count - 1)

        {:noreply,
         socket
         |> assign(:posts_count, new_count)
         # 👈 Instantly removes post from DOM stream
         |> stream_delete(:posts, post)
         |> put_flash(:info, "Post deleted successfully.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete post.")}
    end
  end

  # Event 2: Ingests post & creates local ConstraintProfile template drafts
  @impl true
  def handle_event("save_post", %{"post" => post_params} = params, socket) do
    platforms = Map.get(params, "platforms", ["telegram", "mock_x", "mock_linkedin"])
    socket = assign(socket, :loading, true)

    case Content.ingest_and_template(post_params, platforms) do
      {:ok, {post, _variants}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Content ingested! Constraint templates prepared.")
         # 🚀 Navigates directly to the draft editor page
         |> push_navigate(to: ~p"/posts/#{post.id}")}

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
