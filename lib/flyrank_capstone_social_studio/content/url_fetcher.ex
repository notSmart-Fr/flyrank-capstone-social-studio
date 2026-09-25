defmodule FlyrankCapstoneSocialStudio.Content.UrlFetcher do
  @moduledoc """
  Fetches HTML content from web URLs and extracts clean article text.
  """

  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  @spec fetch_and_extract(binary()) ::
          {:error, :empty_article_content | <<_::64, _::_*8>>} | {:ok, binary()}
  @doc """
  Fetches a URL over HTTP and returns `{:ok, extracted_text}` or `{:error, reason}`.
  """
  def fetch_and_extract(url) when is_binary(url) do
    req_opts = [
      headers: [
        {"user-agent", @user_agent},
        {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"}
      ],
      follow_redirects: true,
      max_redirects: 5,
      receive_timeout: 10_000
    ]

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case extract_article_text(body) do
          "" -> {:error, :empty_article_content}
          text -> {:ok, text}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP request failed with status #{status}"}

      {:error, reason} ->
        {:error, "Failed to reach URL: #{inspect(reason)}"}
    end
  end

  defp extract_article_text(html_body) do
    case Floki.parse_document(html_body) do
      {:ok, document} ->
        cleaned =
          Floki.filter_out(
            document,
            "script, style, nav, footer, header, iframe, noscript, svg, form"
          )

        extracted_nodes =
          case Floki.find(cleaned, "article") do
            [] ->
              case Floki.find(cleaned, "main") do
                [] -> Floki.find(cleaned, "body")
                main_nodes -> main_nodes
              end

            article_nodes ->
              article_nodes
          end

        extracted_nodes
        |> Floki.text(sep: "\n")
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")

      _ ->
        ""
    end
  end
end
