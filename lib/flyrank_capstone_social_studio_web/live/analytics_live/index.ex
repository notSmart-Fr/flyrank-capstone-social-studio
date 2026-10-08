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

    variants = Content.list_variants()
    # Filter for AI generated variants or variants that have undergone grounding check
    ai_variants =
      Enum.reject(variants, fn v ->
        v.model_used == "Local Constraint Template" or is_nil(v.model_used)
      end)

    grounding_rate =
      if Enum.empty?(ai_variants) do
        "N/A"
      else
        grounded_count =
          Enum.count(ai_variants, fn v ->
            v.status in ["draft", "approved", "published"]
          end)

        rate = Float.round(grounded_count / length(ai_variants) * 100, 1)
        "#{rate}%"
      end

    {:ok,
     socket
     |> assign(:page_title, "System Analytics")
     |> assign(:total_posts, total_posts)
     |> assign(:total_cost, total_cost)
     |> assign(:grounding_rate, grounding_rate)
     |> assign(:posts, posts)}
  end
end
