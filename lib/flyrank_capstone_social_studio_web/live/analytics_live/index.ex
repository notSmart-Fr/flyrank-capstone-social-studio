defmodule FlyrankCapstoneSocialStudioWeb.AnalyticsLive.Index do
  use FlyrankCapstoneSocialStudioWeb, :live_view

  alias FlyrankCapstoneSocialStudio.Content

  @impl true
  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(_params, _session, socket) do
    posts = Content.list_posts()

    # Calculate key metrics from existing database records
    total_posts = length(posts)
    # Sum up total_ai_cost from all posts
    total_cost =
      Enum.reduce(posts, Decimal.new("0.00"), fn post, acc ->
        Decimal.add(acc, post.total_ai_cost || Decimal.new("0.00"))
      end)

    {:ok,
     socket
     |> assign(:page_title, "System Analytics")
     |> assign(:total_posts, total_posts)
     |> assign(:total_cost, total_cost)
     |> assign(:posts, posts)}
  end
end
