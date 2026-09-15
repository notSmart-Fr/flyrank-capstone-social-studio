defmodule FlyrankCapstoneSocialStudioWeb.VariantController do
  use FlyrankCapstoneSocialStudioWeb, :controller

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Publishing

  def update(conn, %{"id" => id, "variant" => variant_params}) do
    variant = Content.get_variant!(id)

    case Content.update_variant(variant, variant_params) do
      {:ok, updated} ->
        render(conn, :show, variant: updated)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  def approve(conn, %{"id" => id}) do
    variant = Content.get_variant!(id)

    case Content.approve_variant(variant) do
      {:ok, approved} ->
        render(conn, :show, variant: approved)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  def reject(conn, %{"id" => id} = params) do
    variant = Content.get_variant!(id)
    reason = Map.get(params, "reason", "Rejected by reviewer")

    case Content.reject_variant(variant, reason) do
      {:ok, rejected} ->
        render(conn, :show, variant: rejected)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  def schedule(conn, %{"id" => id} = params) do
    variant = Content.get_variant!(id)
    slot_params = Map.get(params, "slot", %{})

    case Publishing.schedule_variant(variant, slot_params) do
      {:ok, slot} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{slot_id: slot.id, status: slot.status, scheduled_at: slot.scheduled_at}})

      {:error, :unapproved_variant} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Cannot schedule unapproved variant. Current status is '#{variant.status}'."})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end
end
