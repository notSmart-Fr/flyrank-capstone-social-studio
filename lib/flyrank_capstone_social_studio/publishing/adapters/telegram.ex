defmodule FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram do
  @moduledoc """
  Publishes social post content to Telegram channels.
  """

  @behaviour FlyrankCapstoneSocialStudio.Publishing.SocialPublisher

  @spec publish(any()) ::
          {:error, <<_::64, _::_*8>>} | {:ok, %{external_id: binary(), raw_response: <<_::168>>}}
  @max_telegram_characters 4096

  @doc """
  Publishes text to a Telegram channel via the Telegram Bot API.
  Uses a Railway-Oriented pipeline: validate payload -> resolve credentials -> dispatch HTTP.
  """
  @impl true
  def publish(content, opts \\ []) do
    with :ok <- validate_content_payload(content),
         {:ok, token, chat_id} <- resolve_credentials(opts) do
      post_to_telegram(token, chat_id, content, opts)
    end
  end

  # Railway Track 1: Payload Ceiling Verification
  defp validate_content_payload(content) when is_binary(content) do
    if String.length(content) > @max_telegram_characters do
      {:error, "Content exceeds Telegram #{@max_telegram_characters} character limit"}
    else
      :ok
    end
  end

  defp validate_content_payload(_), do: {:error, "Invalid Telegram content"}

  # Railway Track 2: Credential Resolution
  defp resolve_credentials(opts) do
    token =
      System.get_env("TELEGRAM_BOT_TOKEN") ||
        Application.get_env(:flyrank_capstone_social_studio, :telegram_bot_token)

    chat_id =
      Keyword.get(opts, :chat_id) ||
        System.get_env("TELEGRAM_CHAT_ID") ||
        Application.get_env(:flyrank_capstone_social_studio, :telegram_chat_id)

    if token && chat_id do
      {:ok, token, chat_id}
    else
      {:error,
       "Telegram credentials are missing: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are required"}
    end
  end

  # Railway Track 3: HTTP Transmission
  defp post_to_telegram(token, chat_id, content, opts) do
    base_url =
      Application.get_env(
        :flyrank_capstone_social_studio,
        :telegram_base_url,
        "https://api.telegram.org"
      )

    parse_mode = Keyword.get(opts, :parse_mode, "HTML")
    url = "#{base_url}/bot#{token}/sendMessage"

    payload = %{
      chat_id: chat_id,
      text: content,
      parse_mode: parse_mode
    }

    case Req.post(url,
           json: payload,
           finch: [name: FlyrankCapstoneSocialStudio.Finch],
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => %{"message_id" => msg_id}}}} ->
        {:ok, %{external_id: to_string(msg_id), raw_response: "Published to Telegram"}}

      {:ok, %{status: 429} = response} ->
        handle_rate_limit(response)

      {:ok, %{status: status, body: response_body}} ->
        {:error, "Telegram API HTTP #{status}: #{inspect(response_body)}"}

      {:error, reason} ->
        {:error, "Network failure: #{inspect(reason)}"}
    end
  end

  defp handle_rate_limit(%{body: body} = response) do
    retry_after =
      case Req.Response.get_header(response, "retry-after") do
        [val | _] -> parse_seconds(val)
        [] -> get_in(body, ["parameters", "retry_after"])
      end

    if is_integer(retry_after) and retry_after > 0 do
      {:error, {:rate_limited, retry_after}}
    else
      {:error, "Telegram API HTTP 429: #{inspect(body)}"}
    end
  end

  defp parse_seconds(val) when is_integer(val), do: val

  defp parse_seconds(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {seconds, _} when seconds > 0 -> seconds
      _ -> nil
    end
  end

  defp parse_seconds(_), do: nil
end
