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
     |> assign(:posts, posts)
     |> assign(:changeset, changeset)
     |> assign(:loading, false)}
  end

  # Event 1: Validates form input on changes/blur
  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    changeset =
      %Post{}
      |> Content.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  # Event 2: Processes form submission
  @impl true
  def handle_event("save_post", %{"post" => post_params}, socket) do
    # Set loading spinner on submit button
    socket = assign(socket, :loading, true)

    case Content.create_post(post_params) do
      {:ok, post} ->
        # Refresh posts list and reset form
        posts = Content.list_posts()
        changeset = Content.change_post(%Post{})

        {:noreply,
         socket
         |> assign(:posts, posts)
         |> assign(:changeset, changeset)
         |> assign(:loading, false)
         |> put_flash(:info, "Post ingested successfully!")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> assign(:loading, false)
         |> put_flash(:error, "Failed to ingest post. Please check the errors below.")}
    end
  end
end
