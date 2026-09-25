defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Components.InspectorHeader do
  use FlyrankCapstoneSocialStudioWeb, :html

  attr :post, :map, required: true

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <nav
        aria-label="Breadcrumb"
        class="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400"
      >
        <.link navigate={~p"/posts"} class="hover:text-primary-600 dark:hover:text-primary-400">
          Dashboard
        </.link>
        <span>/</span>
        <.link navigate={~p"/posts"} class="hover:text-primary-600 dark:hover:text-primary-400">
          Posts
        </.link>
        <span>/</span>
        <span class="text-gray-900 dark:text-white font-medium truncate max-w-xs">
          {@post.title}
        </span>
      </nav>

      <header class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-gray-200 dark:border-gray-800 pb-5">
        <div>
          <.h2 class="text-gray-900 dark:text-white font-bold text-2xl">{@post.title}</.h2>

          <div class="flex items-center gap-3 mt-2 text-xs text-gray-500 dark:text-gray-400">
            <.badge color="info" variant="outline" label={@post.source_type} />
            <span>Inserted: {Calendar.strftime(@post.inserted_at, "%Y-%m-%d %H:%M UTC")}</span>
          </div>
        </div>

        <div>
          <.link navigate={~p"/posts"}>
            <.button color="gray" variant="outline" size="sm">
              <.icon name="hero-arrow-left-micro" class="w-4 h-4 mr-1" /> Back to Dashboard
            </.button>
          </.link>
        </div>
      </header>
    </div>
    """
  end
end
