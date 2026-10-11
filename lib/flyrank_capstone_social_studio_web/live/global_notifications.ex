defmodule FlyrankCapstoneSocialStudioWeb.GlobalNotifications do
  @moduledoc """
  Lifecycle hook attached to all LiveViews via `live_session :default`.
  Subscribes to global system channels (publishing, grounding, AI generation)
  and pushes floating toaster alerts to the user regardless of which page they are on.
  """
  import Phoenix.LiveView
  alias Phoenix.PubSub

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(FlyrankCapstoneSocialStudio.PubSub, "publishing:events")
      PubSub.subscribe(FlyrankCapstoneSocialStudio.PubSub, "grounding:events")
      PubSub.subscribe(FlyrankCapstoneSocialStudio.PubSub, "ai_generation:events")
    end

    socket = attach_hook(socket, :global_notifications, :handle_info, &handle_info/2)
    {:cont, socket}
  end

  defp handle_info(message, socket) do
    case message do
      {:slot_published, slot} ->
        post_id = slot_post_id(slot)

        if post_id && active_post_view?(socket, post_id) do
          {:cont, socket}
        else
          platform = slot_platform(slot)
          platform_label = if platform, do: " (#{format_platform(platform)})", else: ""

          socket =
            put_flash(
              socket,
              :info,
              "🚀 Post slot ##{slot.id}#{platform_label} published successfully!"
            )

          maybe_cont_or_halt(socket)
        end

      {:slot_failed, slot, error_msg} ->
        post_id = slot_post_id(slot)

        if post_id && active_post_view?(socket, post_id) do
          {:cont, socket}
        else
          platform = slot_platform(slot)
          platform_label = if platform, do: " for #{format_platform(platform)}", else: ""

          socket =
            put_flash(
              socket,
              :error,
              "❌ Publishing failed#{platform_label}: #{error_msg}"
            )

          maybe_cont_or_halt(socket)
        end

      {:slot_rate_limited, slot, seconds} ->
        post_id = slot_post_id(slot)

        if post_id && active_post_view?(socket, post_id) do
          {:cont, socket}
        else
          platform = slot_platform(slot)
          platform_label = if platform, do: " (#{format_platform(platform)})", else: ""

          socket =
            put_flash(
              socket,
              :warning,
              "⏳ Slot ##{slot.id}#{platform_label} rate limited. Snoozed for #{seconds}s"
            )

          maybe_cont_or_halt(socket)
        end

      {:grounding_verified, updated_variant} ->
        if active_post_view?(socket, updated_variant.post_id) do
          {:cont, socket}
        else
          msg =
            case updated_variant.status do
              "draft" ->
                "✅ Grounding verified for Post ##{updated_variant.post_id}! All claims supported by source text."

              "rejected" ->
                "❌ Grounding audit failed for Post ##{updated_variant.post_id}: Unsupported claims detected."

              "needs_review" ->
                "⚠️ Grounding audit incomplete for Post ##{updated_variant.post_id}: #{updated_variant.rejection_reason}"

              _ ->
                "Grounding check complete for Post ##{updated_variant.post_id}."
            end

          flash_type = if updated_variant.status == "draft", do: :info, else: :error
          {:halt, put_flash(socket, flash_type, msg)}
        end

      {:grounding_verification_failed, payload} ->
        variant_post_id = Map.get(payload, :post_id)

        if variant_post_id && active_post_view?(socket, variant_post_id) do
          {:cont, socket}
        else
          reason = Map.get(payload, :reason, "Unknown error")
          {:halt, put_flash(socket, :error, "Grounding verification failed: #{reason}")}
        end

      {:ai_generation_complete, payload} ->
        post_id = Map.get(payload, :post_id)
        platform = Map.get(payload, :platform)

        if post_id && active_post_view?(socket, post_id) do
          {:cont, socket}
        else
          {:halt,
           put_flash(
             socket,
             :info,
             "✨ AI generated variants ready for #{format_platform(platform)}!"
           )}
        end

      {:ai_generation_failed, payload} ->
        post_id = Map.get(payload, :post_id)
        platform = Map.get(payload, :platform)
        reason = Map.get(payload, :reason, "Unknown error")

        if post_id && active_post_view?(socket, post_id) do
          {:cont, socket}
        else
          {:halt,
           put_flash(
             socket,
             :error,
             "AI generation failed for #{format_platform(platform)}: #{reason}"
           )}
        end

      _other ->
        {:cont, socket}
    end
  end

  defp active_post_view?(socket, target_post_id) do
    socket.view == FlyrankCapstoneSocialStudioWeb.PostLive.Show and
      Map.has_key?(socket.assigns, :post) and
      socket.assigns.post != nil and
      socket.assigns.post.id == target_post_id
  end

  defp maybe_cont_or_halt(socket) do
    if socket.view == FlyrankCapstoneSocialStudioWeb.PublishingHistoryLive do
      {:cont, socket}
    else
      {:halt, socket}
    end
  end

  defp format_platform(platform) when is_binary(platform) do
    case platform do
      "mock_x" -> "Mock X"
      "mock_linkedin" -> "Mock LinkedIn"
      "telegram" -> "Telegram"
      other -> String.capitalize(other)
    end
  end

  defp format_platform(platform) when is_atom(platform),
    do: format_platform(to_string(platform))

  defp format_platform(_), do: "Platform"

  defp slot_post_id(%{variant: %FlyrankCapstoneSocialStudio.Content.Variant{post_id: post_id}}),
    do: post_id

  defp slot_post_id(_), do: nil

  defp slot_platform(%{
         variant: %FlyrankCapstoneSocialStudio.Content.Variant{platform: platform}
       }),
       do: platform

  defp slot_platform(_), do: nil
end
