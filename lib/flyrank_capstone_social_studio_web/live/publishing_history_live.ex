defmodule FlyrankCapstoneSocialStudioWeb.PublishingHistoryLive do
  @moduledoc """
  LiveView for inspecting the immutable audit trail of publishing attempts,
  rate-limit events, defense-in-depth constraint guard rejections, and raw adapter payloads.
  """
  use FlyrankCapstoneSocialStudioWeb, :live_view

  alias FlyrankCapstoneSocialStudio.Publishing

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(FlyrankCapstoneSocialStudio.PubSub, "publishing:events")
    end

    attempts = Publishing.list_history()

    {:ok,
     socket
     |> assign(:page_title, "Publishing Audit Trail")
     |> assign(:attempts, attempts)
     |> assign(:selected_attempt, nil)}
  end

  @impl true
  def handle_info({:slot_published, _slot}, socket) do
    {:noreply, assign(socket, :attempts, Publishing.list_history())}
  end

  def handle_info({:slot_failed, _slot, _error}, socket) do
    {:noreply, assign(socket, :attempts, Publishing.list_history())}
  end

  def handle_info({:slot_rate_limited, _slot, _seconds}, socket) do
    {:noreply, assign(socket, :attempts, Publishing.list_history())}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("inspect-attempt", %{"id" => id}, socket) do
    attempt = Publishing.get_publish_attempt!(id)
    {:noreply, assign(socket, :selected_attempt, attempt)}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, :selected_attempt, nil)}
  end

  # Helper functions for UI display
  def status_badge_color("success"), do: "success"
  def status_badge_color("failure"), do: "danger"
  def status_badge_color("pending"), do: "info"
  def status_badge_color(_), do: "warning"

  def platform_badge_color("telegram"), do: "info"
  def platform_badge_color("mock_x"), do: "dark"
  def platform_badge_color("mock_linkedin"), do: "primary"
  def platform_badge_color(_), do: "gray"

  def platform_name("telegram"), do: "Telegram"
  def platform_name("mock_x"), do: "Mock X"
  def platform_name("mock_linkedin"), do: "Mock LinkedIn"
  def platform_name(other), do: other || "Unknown"

  def format_datetime(nil), do: "N/A"
  def format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y %H:%M:%S UTC")

  def format_datetime(%NaiveDateTime{} = ndt),
    do: Calendar.strftime(ndt, "%b %d, %Y %H:%M:%S UTC")
end
