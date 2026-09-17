defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Show do
  use FlyrankCapstoneSocialStudioWeb, :live_view

  alias FlyrankCapstoneSocialStudio.Content

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # 1. Fetch post record with variants preloaded
    post = Content.get_post!(id)

    # 2. Assign initial state into socket assigns
    {:ok,
     socket
     |> assign(:page_title, "Inspect Post: #{post.title}")
     |> assign(:post, post)
     |> assign(:active_tab, "telegram")}
  end

  # Event: Handles active platform tab switching
  @impl true
  def handle_event("select_tab", %{"tab" => tab_name}, socket) do
    {:noreply, assign(socket, :active_tab, tab_name)}
  end
end
