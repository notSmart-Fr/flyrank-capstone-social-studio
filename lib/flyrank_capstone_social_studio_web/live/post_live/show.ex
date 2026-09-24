defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Show do
  use FlyrankCapstoneSocialStudioWeb, :live_view

  alias Phoenix.PubSub
  alias FlyrankCapstoneSocialStudioWeb.PostLive.Queries.PostQuery
  alias FlyrankCapstoneSocialStudioWeb.PostLive.Actions.VariantAction
  alias FlyrankCapstoneSocialStudioWeb.PostLive.Actions.PublishAction
  alias FlyrankCapstoneSocialStudioWeb.PostLive.Actions.AiAction

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    post = PostQuery.get_post_details(id)
    active_tab = "telegram"
    current_variant = PostQuery.find_variant_for_platform(post.variants, active_tab)

    if connected?(socket) do
      PubSub.subscribe(FlyrankCapstoneSocialStudio.PubSub, "post:#{post.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, "Inspect Post: #{post.title}")
     |> assign(:post, post)
     |> assign(:active_tab, active_tab)
     |> assign(:current_variant, current_variant)
     |> assign(:ai_candidates, nil)
     |> assign(:is_unsaved_ai_draft, false)
     |> assign(:show_ab_modal, false)
     |> assign(:show_schedule_modal, false)
     |> assign(:publishing_variant_id, nil)
     |> assign(:generating, PostQuery.oban_generating?(post.id, active_tab))
     |> assign(:canonical_selected, PostQuery.has_ai_variant?(post.variants, active_tab))}
  end

  # ===========================================================================
  # Delegated Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("select_tab", %{"tab" => tab_name}, socket),
    do: VariantAction.select_tab(socket, tab_name)

  @impl true
  def handle_event("save_variant", params, socket),
    do: VariantAction.save_variant(socket, params)

  @impl true
  def handle_event("reject_variant", %{"id" => variant_id}, socket),
    do: VariantAction.reject_variant(socket, variant_id)

  @impl true
  def handle_event("publish_platform", %{"id" => variant_id}, socket),
    do: PublishAction.publish_platform(socket, variant_id)

  @impl true
  def handle_event("open_publish_modal", %{"id" => id}, socket),
    do: PublishAction.open_publish_modal(socket, id)

  @impl true
  def handle_event("close_schedule_modal", _params, socket),
    do: PublishAction.close_schedule_modal(socket)

  @impl true
  def handle_event("confirm_publish", params, socket),
    do: PublishAction.confirm_publish(socket, params)

  @impl true
  def handle_event("generate_platform_variant", %{"platform" => platform}, socket),
    do: AiAction.generate_platform_variant(socket, platform)

  @impl true
  def handle_event("select_ab_choice", %{"choice" => choice}, socket),
    do: AiAction.select_ab_choice(socket, choice)

  @impl true
  def handle_event("close_ab_modal", _params, socket),
    do: {:noreply, assign(socket, :show_ab_modal, false)}

  @impl true
  def handle_event("select_ai_candidate", %{"label" => label}, socket),
    do: VariantAction.select_ai_candidate(socket, label)

  @impl true
  def handle_event("select_variant", %{"variant_id" => variant_id}, socket),
    do: VariantAction.select_variant(socket, variant_id)
    # Oban Worker succeeded -> reload post and inform UI
  @impl true
  def handle_info({:slot_published, _slot}, socket) do
    reloaded_post = PostQuery.get_post_details(socket.assigns.post.id)
    active_variant = PostQuery.find_variant_for_platform(reloaded_post.variants, socket.assigns.active_tab)

    {:noreply,
     socket
     |> assign(:post, reloaded_post)
     |> assign(:current_variant, active_variant)
     |> assign(:generating, false)
     |> put_flash(:info, "🚀 Background Oban job published post successfully!")}
  end

  # Oban Worker failed -> show error flash message
  @impl true
  def handle_info({:slot_failed, _slot, error_msg}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> put_flash(:error, "❌ Background publishing failed: #{error_msg}")}
  end

  # ===========================================================================
  # Delegated Info Callbacks (PubSub / Oban)
  # ===========================================================================

  @impl true
  def handle_info({:ai_generation_complete, payload}, socket),
    do: AiAction.handle_generation_complete(socket, payload)

  @impl true
  def handle_info({:ai_generation_failed, payload}, socket),
    do: AiAction.handle_generation_failed(socket, payload)
end
