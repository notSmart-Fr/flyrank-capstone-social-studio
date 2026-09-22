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
     |> assign(:current_variant, current_variant)
     |> assign(:ai_candidates, nil)
     |> assign(:is_unsaved_ai_draft, false)
     |> assign(:show_ab_modal, false)}
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
     |> assign(:current_variant, current_variant)
     |> assign(:ai_candidates, nil)
     |> assign(:is_unsaved_ai_draft, false)
     |> assign(:show_ab_modal, false)}
  end

  # Event 2: Editing & Saving Variant text edits (Handles both DB records & unsaved AI drafts)
  @impl true
  def handle_event("save_variant", %{"content" => new_content} = params, socket) do
    post = socket.assigns.post
    current_variant = socket.assigns.current_variant

    result =
      if Map.get(socket.assigns, :is_unsaved_ai_draft, false) do
        # Save unsaved in-memory AI draft map into PostgreSQL
        Content.create_variant(
          Map.merge(current_variant, %{
            post_id: post.id,
            content: new_content,
            status: "draft"
          })
        )
      else
        # Update existing DB record
        variant_id = Map.get(params, "variant_id") || Map.get(current_variant, :id)
        variant = Content.get_variant!(variant_id)
        Content.update_variant(variant, %{content: new_content})
      end

    case result do
      {:ok, _saved_variant} ->
        reloaded_post = reload_post(post.id)
        active_variant = find_variant_for_platform(reloaded_post.variants, socket.assigns.active_tab)

        {:noreply,
         socket
         |> assign(:post, reloaded_post)
         |> assign(:current_variant, active_variant)
         |> assign(:ai_candidates, nil)
         |> assign(:is_unsaved_ai_draft, false)
         |> assign(:show_ab_modal, false)
         |> put_flash(:info, "Variant saved to database successfully!")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save variant content.")}
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

    with {:ok, approved_variant} <- ensure_approved(variant),
         {:ok, slot} <- Publishing.schedule_variant(approved_variant, %{scheduled_at: DateTime.utc_now()}, mode: :manual) do

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

  # Event 5: Generating in-memory AI drafts via Gemini Flash on-demand
  @impl true
  def handle_event("generate_platform_variant", %{"platform" => platform}, socket) do
    post = socket.assigns.post

    case Content.generate_ai_drafts(post, platform) do
      {:ok, %{variant_a: draft_a, variant_b: draft_b}} ->
        {:noreply,
         socket
         |> assign(:ai_candidates, %{a: draft_a, b: draft_b})
         |> assign(:show_ab_modal, true)
         |> put_flash(:info, "AI A/B variants generated! Choose your preferred draft.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "AI generation failed: #{inspect(reason)}")}
    end
  end
  # Event 6: User selects Variant A or B from the modal and persists it
  @impl true
  def handle_event("select_ab_choice", %{"choice" => choice}, socket) do
    candidates = socket.assigns.ai_candidates
    post = socket.assigns.post
    platform = socket.assigns.active_tab

    selected_draft = if choice == "B", do: candidates.b, else: candidates.a

    # Auto-save the selected variant directly into PostgreSQL
    variant_params = %{
      post_id: post.id,
      platform: platform,
      variant_label: choice, # "A" or "B"
      content: selected_draft.content,
      status: selected_draft.status,
      rejection_reason: selected_draft.rejection_reason,
      model_used: selected_draft.model_used,
      prompt_tokens: Map.get(selected_draft, :prompt_tokens, 0),
      completion_tokens: Map.get(selected_draft, :completion_tokens, 0),
      total_tokens: Map.get(selected_draft, :total_tokens, 0),
      generation_cost: Map.get(selected_draft, :generation_cost, Decimal.new("0.0"))
    }

    case Content.create_variant(variant_params) do
      {:ok, saved_variant} ->
        # Reload post variants so tab switches instantly recognize the new variant
        updated_post = Content.get_post!(post.id)

        {:noreply,
         socket
         |> assign(:post, updated_post)
         |> assign(:current_variant, saved_variant)
         |> assign(:show_ab_modal, false)
         |> put_flash(:info, "Variant #{choice} saved to database for #{String.upcase(platform)}!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to persist selected variant.")}
    end
  end

  # Event 7: Close modal without choosing a variant
  @impl true
  def handle_event("close_ab_modal", _params, socket) do
    {:noreply, assign(socket, :show_ab_modal, false)}
  end

  # Event 8: Toggle between unsaved A/B candidates in LiveView memory
  @impl true
  def handle_event("select_ai_candidate", %{"label" => label}, socket) do
    candidates = socket.assigns.ai_candidates

    selected =
      case label do
        "B" -> candidates.b
        _ -> candidates.a
      end

    {:noreply,
     socket
     |> assign(:current_variant, selected)
     |> assign(:is_unsaved_ai_draft, true)}
  end

  # Event 9: Switching between persisted DB variants
  @impl true
  def handle_event("select_variant", %{"variant_id" => variant_id}, socket) do
    selected_variant = Content.get_variant!(variant_id)

    {:noreply,
     socket
     |> assign(:current_variant, selected_variant)
     |> assign(:is_unsaved_ai_draft, false)
     |> assign(:show_ab_modal, false)}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp find_variant_for_platform(variants, platform) do
    platform_variants = Enum.filter(variants || [], &(Map.get(&1, :platform) == platform))

    ai_variant =
      platform_variants
      |> Enum.filter(fn v ->
        model = Map.get(v, :model_used)
        model && model != "Local Constraint Template"
      end)
      |> List.last()

    ai_variant || List.last(platform_variants)
  end

  defp reload_post(post_id) do
    Content.get_campaign_details(post_id) || Content.get_post!(post_id)
  end

  defp ensure_approved(%{status: "approved"} = variant), do: {:ok, variant}
  defp ensure_approved(variant), do: Content.approve_variant(variant)
end
