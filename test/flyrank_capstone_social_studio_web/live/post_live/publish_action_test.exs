defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Actions.PublishActionTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing.Slot
  alias FlyrankCapstoneSocialStudio.Publishing.Workers.PublishWorker
  alias FlyrankCapstoneSocialStudio.Test.FailingPublisher
  alias FlyrankCapstoneSocialStudioWeb.PostLive.Actions.PublishAction

  setup do
    {:ok, post} =
      Content.create_post(%{
        title: "Publish Action Post",
        content: "Publishing from the inspector modal.",
        source_type: "markdown"
      })

    {:ok, variant} =
      Content.create_variant(%{
        post_id: post.id,
        platform: "mock_x",
        content: "Modal publish content #tech",
        status: "draft"
      })

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        post: post,
        current_variant: variant,
        show_schedule_modal: true,
        publishing_variant_id: variant.id
      }
    }

    %{socket: socket, variant: variant}
  end

  defp slot_for(variant), do: Repo.one!(from s in Slot, where: s.variant_id == ^variant.id)

  describe "Publish Modal Behavior: instant & scheduled confirmation" do
    @describetag :publishing
    @describetag :publish_ui

    test "instant mode approves, dispatches, closes the modal and flashes success", %{
      socket: socket,
      variant: variant
    } do
      assert {:noreply, socket} = PublishAction.confirm_publish(socket, %{"mode" => "now"})

      assert socket.assigns.flash["info"] =~ "Successfully published to MOCK_X"
      assert socket.assigns.show_schedule_modal == false
      assert socket.assigns.publishing_variant_id == nil
      assert socket.assigns.current_variant.status == "published"
      assert slot_for(variant).status == "published"
      refute_enqueued(worker: PublishWorker)
    end

    test "scheduled mode queues a job for the chosen time and flashes the schedule", %{
      socket: socket,
      variant: variant
    } do
      params = %{"mode" => "scheduled", "scheduled_at" => "2099-01-01T10:30"}

      assert {:noreply, socket} = PublishAction.confirm_publish(socket, params)

      assert socket.assigns.flash["info"] =~ "Post scheduled for Jan 01, 2099 at 10:30 UTC"
      assert socket.assigns.show_schedule_modal == false
      assert slot_for(variant).status == "pending"
      assert_enqueued(worker: PublishWorker, args: %{"slot_id" => slot_for(variant).id})
      assert Content.get_variant!(variant.id).status == "approved"
    end

    @tag :error_handling
    test "scheduled mode with an unparseable time falls back to now instead of crashing", %{
      socket: socket
    } do
      params = %{"mode" => "scheduled", "scheduled_at" => "not-a-date"}

      assert {:noreply, socket} = PublishAction.confirm_publish(socket, params)
      assert socket.assigns.flash["info"] =~ "Post scheduled for"
    end
  end

  describe "Publish Modal Failure Behavior: errors surface as flash messages" do
    @describetag :publishing
    @describetag :publish_ui
    @describetag :error_handling

    test "adapter failure flashes 'Dispatch failed' and marks the slot failed", %{
      socket: socket,
      variant: variant
    } do
      FailingPublisher.swap_adapter!(:mock_x, FailingPublisher)

      assert {:noreply, socket} = PublishAction.confirm_publish(socket, %{"mode" => "now"})

      assert socket.assigns.flash["error"] =~ "Dispatch failed"
      assert socket.assigns.show_schedule_modal == false
      assert slot_for(variant).status == "failed"
    end

    test "a rejected variant cannot be published and stays rejected", %{
      socket: socket,
      variant: variant
    } do
      {:ok, rejected} = Content.update_variant(variant, %{status: "rejected"})
      socket = put_in(socket.assigns.current_variant, rejected)

      assert {:noreply, socket} = PublishAction.confirm_publish(socket, %{"mode" => "now"})

      assert socket.assigns.flash["error"] =~ "Cannot publish a rejected variant"
      assert Content.get_variant!(variant.id).status == "rejected"
      assert Repo.all(from s in Slot, where: s.variant_id == ^variant.id) == []
    end

    test "an already published variant cannot be published again", %{
      socket: socket,
      variant: variant
    } do
      {:ok, published} = Content.update_variant(variant, %{status: "published"})
      socket = put_in(socket.assigns.current_variant, published)

      assert {:noreply, socket} = PublishAction.confirm_publish(socket, %{"mode" => "now"})

      assert socket.assigns.flash["error"] =~ "Cannot publish a published variant"
    end

    test "a past scheduled time flashes 'Publishing failed' and closes the modal", %{
      socket: socket
    } do
      params = %{"mode" => "scheduled", "scheduled_at" => "2000-01-01T00:00"}

      assert {:noreply, socket} = PublishAction.confirm_publish(socket, params)

      assert socket.assigns.flash["error"] =~ "Publishing failed"
      assert socket.assigns.show_schedule_modal == false
      assert socket.assigns.publishing_variant_id == nil
    end
  end
end
