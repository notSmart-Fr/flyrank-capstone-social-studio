defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Show do
  use FlyrankCapstoneSocialStudioWeb, :live_view

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Fetch campaign details with variants preloaded
    post = Content.get_campaign_details(id) || Content.get_post!(id)
    active_tab = "telegram"
    current_variant = find_variant_for_platform(post.variants, active_tab)

    {:ok,
     socket
     |> assign(:page_title, "Inspect Post: #{post.title}")
     |> assign(:post, post)
     |> assign(:active_tab, active_tab)
     |> assign(:current_variant, current_variant)}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  # Event 1: Tab switching
  @impl true
  def handle_event("select_tab", %{"tab" => tab_name}, socket) do
    current_variant = find_variant_for_platform(socket.assigns.post.variants, tab_name)

    {:noreply,
     socket
     |> assign(:active_tab, tab_name)
     |> assign(:current_variant, current_variant)}
  end

  # Event 2: Editing & Saving Variant text edits
  @impl true
  def handle_event("save_variant", %{"variant_id" => variant_id, "content" => new_content}, socket) do
    variant = Content.get_variant!(variant_id)

    case Content.update_variant(variant, %{content: new_content}) do
      {:ok, updated_variant} ->
        post = reload_post(socket.assigns.post.id)

        {:noreply,
         socket
         |> assign(:post, post)
         |> assign(:current_variant, updated_variant)
         |> put_flash(:info, "Variant content updated successfully!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update variant content.")}
    end
  end

  # Event 3: Rejecting a Variant
  @impl true
  def handle_event("reject_variant", %{"id" => variant_id}, socket) do
    variant = Content.get_variant!(variant_id)

    case Content.reject_variant(variant, "Rejected by user in inspector") do
      {:ok, rejected_variant} ->
        post = reload_post(socket.assigns.post.id)

        {:noreply,
         socket
         |> assign(:post, post)
         |> assign(:current_variant, rejected_variant)
         |> put_flash(:info, "Variant status marked as rejected.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reject variant.")}
    end
  end

  # Event 4: Approving & Scheduling/Posting Variant to Platform
  @impl true
  def handle_event("publish_platform", %{"id" => variant_id}, socket) do
    variant = Content.get_variant!(variant_id)

    # 1. Ensure variant is approved (required by Publishing.schedule_variant/3)
    with {:ok, approved_variant} <- ensure_approved(variant),
         # 2. Schedule variant into publishing queue (or dispatch immediately)
         {:ok, slot} <- Publishing.schedule_variant(approved_variant, %{scheduled_at: DateTime.utc_now()}, mode: :manual) do

      # 3. Trigger immediate dispatch
      case Publishing.dispatch_slot(slot) do
        {:ok, _attempt} ->
          post = reload_post(socket.assigns.post.id)

          {:noreply,
           socket
           |> assign(:post, post)
           |> assign(:current_variant, approved_variant)
           |> put_flash(:info, "Successfully dispatched and published post to #{String.upcase(approved_variant.platform)}!")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Dispatch failed: #{inspect(reason)}")}
      end
    else
      {:error, :unapproved_variant} ->
        {:noreply, put_flash(socket, :error, "Cannot publish an unapproved variant.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Publishing failed: #{inspect(reason)}")}
    end
  end

 # Event 5: Generating Variant on-demand via Gemini Flash
  @impl true
  def handle_event("generate_platform_variant", %{"platform" => platform}, socket) do
    post = socket.assigns.post

    case Content.generate_variant_for_platform(post, platform) do
      {:ok, _variants} ->
        reloaded_post = reload_post(post.id)
        current_variant = find_variant_for_platform(reloaded_post.variants, platform)

        {:noreply,
         socket
         |> assign(:post, reloaded_post)
         |> assign(:current_variant, current_variant)
         |> put_flash(:info, "Generated grounded AI variants for #{String.upcase(platform)} via Gemini Flash!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "AI generation failed: #{inspect(reason)}")}
    end
  end
# Event: Switching between A/B variants for the current platform
  @impl true
  def handle_event("select_variant", %{"variant_id" => variant_id}, socket) do
    selected_variant = Content.get_variant!(variant_id)

    {:noreply, assign(socket, :current_variant, selected_variant)}
  end
  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp find_variant_for_platform(variants, platform) when is_list(variants) do
    Enum.find(variants, fn v ->
      v.platform == platform or (platform in ["x", "mock_x"] and v.platform in ["x", "mock_x"])
    end)
  end

  defp find_variant_for_platform(_variants, _platform), do: nil

  defp reload_post(post_id) do
    Content.get_campaign_details(post_id) || Content.get_post!(post_id)
  end

  defp ensure_approved(%{status: "approved"} = variant), do: {:ok, variant}
  defp ensure_approved(variant), do: Content.approve_variant(variant)
end
