defmodule FlyrankCapstoneSocialStudioWeb.Plugs.RateLimiter do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @spec init(keyword()) :: %{limit: any(), scale_ms: any()}
  @doc """
  Options:
  - `:scale_ms` - Time window in milliseconds (e.g., 10_000 for 10 seconds)
  - `:limit` - Max requests allowed within that window (e.g., 5)
  """
  def init(opts) do
    %{
      scale_ms: Keyword.get(opts, :scale_ms, 10_000),
      limit: Keyword.get(opts, :limit, 5)
    }
  end

  @spec call(Plug.Conn.t(), %{limit: any(), scale_ms: any()}) :: Plug.Conn.t()
  def call(conn, opts) do
    # Identify key by user_id if authenticated, or fallback to remote IP
    client_id = get_client_id(conn)
    bucket_key = "req_limit:#{conn.request_path}:#{client_id}"

    case Hammer.check_rate(bucket_key, opts.scale_ms, opts.limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        # 429
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", to_string(div(opts.scale_ms, 1000)))
        |> json(%{
          error: "Rate limit exceeded. Please wait before retrying.",
          retry_after_seconds: div(opts.scale_ms, 1000)
        })
        |> halt()
    end
  end

  defp get_client_id(conn) do
    case conn.assigns[:current_user] do
      %{id: user_id} -> "user:#{user_id}"
      _ -> "ip:#{to_string(:inet.ntoa(conn.remote_ip))}"
    end
  end
end
