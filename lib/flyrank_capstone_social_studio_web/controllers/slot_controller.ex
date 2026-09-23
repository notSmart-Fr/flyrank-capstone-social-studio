defmodule FlyrankCapstoneSocialStudioWeb.SlotController do
  use FlyrankCapstoneSocialStudioWeb, :controller

  alias FlyrankCapstoneSocialStudio.Publishing

  def publish(conn, %{"id" => id}) do
    slot = Publishing.get_slot!(id)

    case Publishing.dispatch_slot(slot) do
      {:ok, attempt} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: %{
            slot_id: slot.id,
            status: attempt.status,
            external_post_id: attempt.external_post_id,
            attempted_at: attempt.attempted_at,
            raw_response: attempt.raw_response
          }
        })

      {:error, attempt} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Publishing failed",
          details: attempt.error_message
        })
    end
  end
end
