defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Actions.AiAction do
  use FlyrankCapstoneSocialStudioWeb, :html

  def ai_action(assigns)
  embed_templates "ai_action.html"

  @moduledoc """
  Encapsulates Oban job queuing, A/B candidate selection, and PubSub results.
  """
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Content.GenerateAiVariants
  alias FlyrankCapstoneSocialStudioWeb.PostLive.Queries.PostQuery

  @spec generate_platform_variant(any(), any()) :: {:noreply, any()}
  def generate_platform_variant(socket, platform) do
    post = socket.assigns.post

    if PostQuery.oban_generating?(post.id, platform) do
      {:noreply,
       socket
       |> assign(:active_tab, platform)
       |> assign(:generating, true)
       |> put_flash(:info, "AI generation is already in progress for #{platform}.")}
    else
      case %{post_id: post.id, platform: platform}
           |> GenerateAiVariants.Worker.new()
           |> Oban.insert() do
        {:ok, _job} ->
          {:noreply, assign(socket, generating: true, active_tab: platform)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:generating, false)
           |> put_flash(:error, "AI generation could not be queued: #{inspect(reason)}")}
      end
    end
  end

  def select_ab_choice(socket, choice) do
    candidates = socket.assigns.ai_candidates
    post = socket.assigns.post
    platform = socket.assigns.active_tab

    selected_draft = if choice == "B", do: candidates.b, else: candidates.a

    variant_params = %{
      post_id: post.id,
      platform: platform,
      variant_label: choice,
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
        updated_post = PostQuery.get_post_details(post.id)

        {:noreply,
         socket
         |> assign(:post, updated_post)
         |> assign(:current_variant, saved_variant)
         |> assign(:show_ab_modal, false)
         |> assign(:canonical_selected, true)
         |> put_flash(
           :info,
           "Variant #{choice} saved to database for #{String.upcase(platform)}!"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to persist selected variant.")}
    end
  end

  def handle_generation_complete(socket, %{a: draft_a, b: draft_b}) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> assign(:ai_candidates, %{a: draft_a, b: draft_b})
     |> assign(:show_ab_modal, true)
     |> put_flash(:info, "AI A/B variants generated! Choose your preferred draft.")}
  end

  def handle_generation_failed(socket, %{reason: reason}) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> put_flash(:error, "AI generation failed: #{reason}")}
  end
end
