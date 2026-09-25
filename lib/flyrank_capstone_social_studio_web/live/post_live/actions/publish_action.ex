defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Actions.PublishAction do
  use FlyrankCapstoneSocialStudioWeb, :html

  @spec publish_action(any()) :: Phoenix.LiveView.Rendered.t()
  def publish_action(assigns)
  embed_templates "publish_action.html"

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  @moduledoc """
  Handles mode switching between Instant Posting and Custom DateTime Scheduling.
  """

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudioWeb.PostLive.Queries.PostQuery

  @spec publish_platform(map(), any()) :: {:noreply, map()}
  def publish_platform(socket, variant_id), do: open_publish_modal(socket, variant_id)

  # Modal Trigger: Opens modal and sets current target variant
  def open_publish_modal(socket, variant_id) do
    {:noreply,
     socket
     |> assign(:show_schedule_modal, true)
     |> assign(:publishing_variant_id, variant_id)}
  end

  @spec close_schedule_modal(map()) :: {:noreply, map()}
  def close_schedule_modal(socket) do
    {:noreply,
     socket
     |> assign(:show_schedule_modal, false)
     |> assign(:publishing_variant_id, nil)}
  end

  # Confirmation Handler: Executes Instant or Custom Scheduled post
  def confirm_publish(socket, params) do
    variant_id = socket.assigns[:publishing_variant_id] || socket.assigns.current_variant.id
    variant = Content.get_variant!(variant_id)
    mode = Map.get(params, "mode") || Map.get(params, "value") || "now"

    scheduled_at =
      case mode do
        "scheduled" ->
          case Map.get(params, "scheduled_at") do
            nil ->
              DateTime.utc_now()

            dt_str ->
              case DateTime.from_iso8601("#{dt_str}:00Z") do
                {:ok, dt, _offset} -> dt
                _ -> DateTime.utc_now()
              end
          end

        _now ->
          DateTime.utc_now()
      end

    with {:ok, approved_variant} <- ensure_approved(variant),
         {:ok, slot} <-
           Publishing.schedule_variant(approved_variant, %{scheduled_at: scheduled_at},
             mode: :manual,
             enqueue: mode != "now"
           ) do
      if mode == "now" do
        # Instant mode: Dispatch immediately
        case Publishing.dispatch_slot(slot) do
          {:ok, _attempt} ->
            post = PostQuery.get_post_details(socket.assigns.post.id)

            updated_variant =
              Enum.find(post.variants, &(&1.id == approved_variant.id)) || approved_variant

            {:noreply,
             socket
             |> assign(:post, post)
             |> assign(:current_variant, updated_variant)
             |> assign(:show_schedule_modal, false)
             |> assign(:publishing_variant_id, nil)
             |> put_flash(
               :info,
               "🚀 Successfully published to #{String.upcase(approved_variant.platform)}!"
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:show_schedule_modal, false)
             |> assign(:publishing_variant_id, nil)
             |> put_flash(:error, "Dispatch failed: #{inspect(reason)}")}
        end
      else
        # Scheduled mode: Queue for Oban/background runner
        post = PostQuery.get_post_details(socket.assigns.post.id)

        {:noreply,
         socket
         |> assign(:post, post)
         |> assign(:show_schedule_modal, false)
         |> assign(:publishing_variant_id, nil)
         |> put_flash(
           :info,
           "📅 Post scheduled for #{Calendar.strftime(scheduled_at, "%b %d, %Y at %H:%M UTC")}!"
         )}
      end
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:show_schedule_modal, false)
         |> assign(:publishing_variant_id, nil)
         |> put_flash(:error, "Publishing failed: #{inspect(reason)}")}
    end
  end

  defp ensure_approved(%{status: "approved"} = variant), do: {:ok, variant}
  defp ensure_approved(variant), do: Content.approve_variant(variant)
end
