defmodule FlyrankCapstoneSocialStudioWeb.Plugs.IdempotencyLock do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  alias FlyrankCapstoneSocialStudio.Content.IdempotencyKey
  alias FlyrankCapstoneSocialStudio.Repo

  @spec init(any()) :: any()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case get_req_header(conn, "idempotency-key") do
      [key] when byte_size(key) > 0 ->
        # Check if the key already exists in DB
        case Repo.get_by(IdempotencyKey, key: key) do
          # 1. Previously completed -> Return cached response immediately without touching controller
          %IdempotencyKey{status: "completed", response_payload: payload} ->
            conn
            |> put_status(:ok)
            |> json(payload)
            |> halt()

          # 2. Currently in flight -> Return 409 Conflict immediately
          %IdempotencyKey{status: "processing"} ->
            conn
            |> put_status(:conflict)
            |> json(%{error: "A request with this Idempotency-Key is currently in flight."})
            |> halt()

          # 3. Key does not exist yet -> Let the controller & Content context manage execution & locking
          nil ->
            conn
        end

      _ ->
        conn
    end
  end
end
