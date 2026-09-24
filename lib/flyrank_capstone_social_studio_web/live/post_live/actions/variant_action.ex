defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Actions.VariantAction do
  use FlyrankCapstoneSocialStudioWeb, :html

  def variant_action(assigns)
  embed_templates "variant_action.html"

  @moduledoc """
  Handles UI navigation, manual editing, saving, and rejecting of variants.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudioWeb.PostLive.Queries.PostQuery

  def select_tab(socket, tab_name) do
    post = socket.assigns.post
    current_variant = PostQuery.find_variant_for_platform(post.variants, tab_name)
    generating = PostQuery.oban_generating?(post.id, tab_name)

    {:noreply,
     socket
     |> assign(:active_tab, tab_name)
     |> assign(:current_variant, current_variant)
     |> assign(:ai_candidates, nil)
     |> assign(:is_unsaved_ai_draft, false)
     |> assign(:show_ab_modal, false)
     |> assign(:generating, generating)
     |> assign(:canonical_selected, PostQuery.has_ai_variant?(post.variants, tab_name))}
  end

  def save_variant(socket, %{"content" => new_content} = params) do
    post = socket.assigns.post
    current_variant = socket.assigns.current_variant

    result =
      if Map.get(socket.assigns, :is_unsaved_ai_draft, false) do
        Content.create_variant(
          Map.merge(current_variant, %{
            post_id: post.id,
            content: new_content,
            status: "draft"
          })
        )
      else
        variant_id = Map.get(params, "variant_id") || Map.get(current_variant, :id)
        variant = Content.get_variant!(variant_id)
        Content.update_variant(variant, %{content: new_content})
      end

    case result do
      {:ok, _saved_variant} ->
        reloaded_post = PostQuery.get_post_details(post.id)

        active_variant =
          PostQuery.find_variant_for_platform(reloaded_post.variants, socket.assigns.active_tab)

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

  def reject_variant(socket, variant_id) do
    variant = Content.get_variant!(variant_id)

    case Content.reject_variant(variant, "Rejected by user in inspector") do
      {:ok, rejected_variant} ->
        post = PostQuery.get_post_details(socket.assigns.post.id)

        {:noreply,
         socket
         |> assign(:post, post)
         |> assign(:current_variant, rejected_variant)
         |> put_flash(:info, "Variant status marked as rejected.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reject variant.")}
    end
  end

  def select_variant(socket, variant_id) do
    selected_variant = Content.get_variant!(variant_id)

    {:noreply,
     socket
     |> assign(:current_variant, selected_variant)
     |> assign(:is_unsaved_ai_draft, false)
     |> assign(:show_ab_modal, false)}
  end

  def select_ai_candidate(socket, label) do
    candidates = socket.assigns.ai_candidates
    selected = if label == "B", do: candidates.b, else: candidates.a

    {:noreply,
     socket
     |> assign(:current_variant, selected)
     |> assign(:is_unsaved_ai_draft, true)}
  end
end
