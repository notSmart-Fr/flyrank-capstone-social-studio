defmodule FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram do
  @behaviour FlyrankCapstoneSocialStudio.Publishing.SocialPublisher

  @doc """
  Publishes text to a Telegram channel via the Telegram Bot API.
  """
  @impl true
  def publish(content, opts \\ []) do
    token =
      System.get_env("TELEGRAM_BOT_TOKEN") ||
        Application.get_env(:flyrank_capstone_social_studio, :telegram_bot_token)

    chat_id =
      Keyword.get(opts, :chat_id) ||
        System.get_env("TELEGRAM_CHAT_ID") ||
        Application.get_env(:flyrank_capstone_social_studio, :telegram_chat_id)

    if token && chat_id do
      url = "https://api.telegram.org/bot#{token}/sendMessage"

      payload = %{
        chat_id: chat_id,
        text: content,
        # Enables bold, italic, and links in Telegram
        parse_mode: "Markdown"
      }

      # Req handles JSON encoding and content-type headers automatically via `json:`
      case Req.post(url, json: payload, finch: FlyrankCapstoneSocialStudio.Finch) do
        {:ok, %{status: 200, body: %{"ok" => true, "result" => %{"message_id" => msg_id}}}} ->
          {:ok, %{external_id: to_string(msg_id), raw_response: "Published to Telegram"}}

        {:ok, %{status: status, body: response_body}} ->
          {:error, "Telegram API HTTP #{status}: #{inspect(response_body)}"}

        {:error, reason} ->
          {:error, "Network failure: #{inspect(reason)}"}
      end
    else
      {:error, "Telegram credentials are missing: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are required"}
    end
  end
end
