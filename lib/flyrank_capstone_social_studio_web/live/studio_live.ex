defmodule FlyrankCapstoneSocialStudioWeb.StudioLive do
  use FlyrankCapstoneSocialStudioWeb, :live_view

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      FlyrankCapstoneSocialStudioWeb.Endpoint.subscribe("publishing:events")
    end

    posts = Content.list_posts()
    history = Publishing.list_history()
    selected_post = if first_post = List.first(posts), do: Content.get_campaign_details(first_post.id)

    {:ok,
     assign(socket,
       posts: posts,
      selected_post: selected_post,
       history: history,
       new_title: "",
       new_content: "",
       selected_platforms: ["telegram", "mock_x", "mock_linkedin"]
     )}
  end

  @impl true
  def handle_event("toggle_platform", %{"platform" => platform}, socket) do
    platforms = socket.assigns.selected_platforms
    updated = if platform in platforms, do: List.delete(platforms, platform), else: [platform | platforms]
    {:noreply, assign(socket, selected_platforms: updated)}
  end

  @impl true
  def handle_event("ingest", %{"title" => title, "content" => content}, socket) do
    platforms = socket.assigns.selected_platforms

    if platforms == [] do
      {:noreply, put_flash(socket, :error, "Select at least one platform.")}
    else
      case Content.ingest_and_generate(%{title: title, content: content, source_type: "markdown"}, platforms) do
        {:ok, {post, _variants}} ->
          posts = Content.list_posts()
          selected_post = Content.get_campaign_details(post.id)
          {:noreply, assign(socket, posts: posts, selected_post: selected_post, new_title: "", new_content: "")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to ingest post.")}
      end
    end
  end

  @impl true
  def handle_event("select_post", %{"id" => id}, socket) do
    selected_post = Content.get_campaign_details(String.to_integer(id))
    {:noreply, assign(socket, selected_post: selected_post)}
  end

  @impl true
  def handle_event("approve_variant", %{"id" => id}, socket) do
    variant = Content.get_variant!(String.to_integer(id))
    Content.approve_variant(variant)
    selected_post = Content.get_campaign_details(socket.assigns.selected_post.id)
    {:noreply, assign(socket, selected_post: selected_post)}
  end

  @impl true
  def handle_event("reject_variant", %{"id" => id}, socket) do
    variant = Content.get_variant!(String.to_integer(id))
    Content.reject_variant(variant, "Rejected via UI")
    selected_post = Content.get_campaign_details(socket.assigns.selected_post.id)
    {:noreply, assign(socket, selected_post: selected_post)}
  end

  @impl true
  def handle_event("schedule_variant", %{"id" => id}, socket) do
    variant = Content.get_variant!(String.to_integer(id))
    scheduled_at = DateTime.utc_now()

    case Publishing.schedule_variant(variant, %{"scheduled_at" => scheduled_at, "idempotency_key" => "ui-key-variant-#{variant.id}"}) do
      {:ok, _slot} ->
        selected_post = Content.get_campaign_details(socket.assigns.selected_post.id)
        history = Publishing.list_history()
        {:noreply,
         socket
         |> assign(selected_post: selected_post, history: history)
         |> put_flash(:info, "Publishing started. Repeated clicks will not create another publication.")}

      {:error, :unapproved_variant} ->
        {:noreply, put_flash(socket, :error, "Cannot schedule an unapproved variant.")}
    end
  end

  @impl true
  def handle_info({:slot_published, _slot}, socket) do
    selected_post = if socket.assigns.selected_post, do: Content.get_campaign_details(socket.assigns.selected_post.id), else: nil
    history = Publishing.list_history()
    {:noreply, assign(socket, selected_post: selected_post, history: history)}
  end

  @impl true
  def handle_info({:slot_failed, _slot}, socket) do
    selected_post = if socket.assigns.selected_post, do: Content.get_campaign_details(socket.assigns.selected_post.id), else: nil
    history = Publishing.list_history()

    {:noreply,
     socket
     |> assign(selected_post: selected_post, history: history)
     |> put_flash(:error, "Publishing failed. You can retry the publication.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-6 font-sans">
      <header class="navbar bg-base-100 shadow-xl rounded-box mb-6 px-6">
        <h1 class="text-2xl font-bold text-primary flex-1">Social Studio</h1>
        <span class="badge badge-accent font-mono">Tailwind v4 + LiveView</span>
      </header>

      <main class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <aside class="space-y-6">
          <.ingestion_form
            new_title={@new_title}
            new_content={@new_content}
            selected_platforms={@selected_platforms}
          />
          <.campaign_list posts={@posts} selected_post={@selected_post} />
        </aside>

        <section class="lg:col-span-2 space-y-6">
          <.campaign_workspace post={@selected_post} />
          <.history_table history={@history} />
        </section>
      </main>
    </div>
    """
  end
end
