defmodule FlyrankCapstoneSocialStudioWeb.StudioComponents do
  use Phoenix.Component

  attr :selected_platforms, :list, required: true
  attr :new_title, :string, required: true
  attr :new_content, :string, required: true

  def ingestion_form(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-secondary">Ingest Blog Post</h2>
        <form phx-submit="ingest" class="space-y-4">
          <fieldset class="space-y-1">
            <label class="label text-xs font-semibold">Post Title</label>
            <input type="text" name="title" value={@new_title} placeholder="Title..." class="input input-bordered w-full" required />
          </fieldset>

          <fieldset class="space-y-1">
            <label class="label text-xs font-semibold">Markdown Content</label>
            <textarea name="content" placeholder="Content..." class="textarea textarea-bordered w-full h-24" required>{@new_content}</textarea>
          </fieldset>

          <fieldset class="space-y-1">
            <label class="label text-xs font-semibold">Target Platforms</label>
            <div class="flex flex-col gap-2">
              <%= for {key, label} <- platform_options() do %>
                <label class="cursor-pointer flex items-center gap-2 bg-base-200 p-2 rounded border border-base-300">
                  <input type="checkbox" checked={key in @selected_platforms} phx-click="toggle_platform" phx-value-platform={key} class="checkbox checkbox-primary checkbox-sm" />
                  <span class="text-xs font-bold">{label}</span>
                </label>
              <% end %>
            </div>
          </fieldset>

          <button type="submit" class="btn btn-primary w-full mt-2 phx-submit-loading:loading" phx-disable-with="Generating">
            Ingest & Generate Selected
          </button>
        </form>
      </div>
    </section>
    """
  end

  attr :posts, :list, required: true
  attr :selected_post, :any, default: nil

  def campaign_list(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-md">Campaign Posts</h2>
        <ul class="menu bg-base-200 w-full rounded-box">
          <%= for post <- @posts do %>
            <li>
              <a
                phx-click="select_post"
                phx-value-id={post.id}
                class={if @selected_post && @selected_post.id == post.id, do: "active font-bold", else: ""}
              >
                {post.title}
              </a>
            </li>
          <% end %>
        </ul>
      </div>
    </section>
    """
  end

  attr :post, :any, default: nil

  def campaign_workspace(assigns) do
    ~H"""
    <%= if @post do %>
      <article class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <header class="border-b border-base-300 pb-3">
            <h2 class="card-title text-xl text-primary font-bold">Campaign: {@post.title}</h2>
            <p class="text-xs opacity-70 mt-1">{@post.content}</p>
          </header>

          <section class="mt-4">
            <h3 class="font-semibold text-sm mb-3">Generated Target Variants</h3>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <%= for variant <- @post.variants do %>
                <.variant_card variant={variant} />
              <% end %>
            </div>
          </section>
        </div>
      </article>
    <% end %>
    """
  end

  attr :variant, :map, required: true

  def variant_card(assigns) do
    ~H"""
    <article class="card bg-base-200 border border-base-300">
      <div class="card-body p-4">
        <header class="flex justify-between items-center">
          <span class="badge badge-outline uppercase font-mono font-bold">{@variant.platform}</span>
          <.status_badge status={@variant.status} />
        </header>

        <p class="text-xs my-3 bg-base-100 p-2 rounded min-h-20 whitespace-pre-wrap">{@variant.content}</p>

        <footer class="card-actions justify-end gap-1 mt-2 min-h-8">
          <%= if @variant.status in ["draft", "rejected"] do %>
            <button phx-click="approve_variant" phx-value-id={@variant.id} class="btn btn-xs btn-success text-white">Approve</button>
          <% end %>
          <%= if @variant.status in ["draft", "approved"] do %>
            <button phx-click="reject_variant" phx-value-id={@variant.id} class="btn btn-xs btn-error text-white">Reject</button>
          <% end %>
          <%= if @variant.status == "approved" do %>
            <%= case latest_slot_status(@variant) do %>
              <% "pending" -> %>
                <button class="btn btn-xs btn-primary loading" disabled>Scheduled for publish</button>
              <% "failed" -> %>
                <button phx-click="schedule_variant" phx-value-id={@variant.id} class="btn btn-xs btn-warning phx-click-loading:pointer-events-none phx-click-loading:loading" phx-disable-with="Retrying...">Retry publish</button>
              <% _ -> %>
                <button phx-click="schedule_variant" phx-value-id={@variant.id} class="btn btn-xs btn-primary phx-click-loading:pointer-events-none phx-click-loading:loading" phx-disable-with="Publishing...">Publish Now</button>
            <% end %>
          <% end %>
          <%= if @variant.status == "published" do %>
            <span class="text-xs text-success font-semibold py-1">Sent</span>
          <% end %>
        </footer>
      </div>
    </article>
    """
  end

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={["badge text-white", status_class(@status)]}>{@status}</span>
    """
  end

  attr :history, :list, required: true

  def history_table(assigns) do
    ~H"""
    <section class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-md">Publishing History Audit Log</h2>
        <div class="overflow-x-auto">
          <table class="table table-xs w-full">
            <thead><tr><th>Platform</th><th>Slot</th><th>Status</th><th>External ID</th><th>Attempted At</th></tr></thead>
            <tbody>
              <%= for attempt <- @history do %>
                <tr>
                  <td>{attempt.slot.variant.platform}</td>
                  <td>{attempt.slot_id}</td>
                  <td><.status_badge status={attempt.status} /></td>
                  <td class="font-mono">{attempt.external_post_id}</td>
                  <td>{attempt.inserted_at}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  defp platform_options do
    [{"telegram", "Telegram"}, {"mock_x", "X (Twitter)"}, {"mock_linkedin", "LinkedIn"}]
  end

  defp latest_slot_status(%{slots: slots}) when is_list(slots) do
    case Enum.max_by(slots, & &1.inserted_at, fn -> nil end) do
      nil -> nil
      slot -> slot.status
    end
  end

  defp latest_slot_status(_variant), do: nil

  defp status_class("approved"), do: "badge-success"
  defp status_class("rejected"), do: "badge-error"
  defp status_class("published"), do: "badge-info"
  defp status_class("success"), do: "badge-success"
  defp status_class(_status), do: "badge-warning"
end
