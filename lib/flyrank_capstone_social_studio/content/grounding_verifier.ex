defmodule FlyrankCapstoneSocialStudio.Content.GroundingVerifier do
  @moduledoc """
  Verifies that factual claims in a generated variant are supported by the source post using Gemini.
  """

  @type grounding_result ::
          {:ok, :grounded}
          | {:error, :hallucination_detected, list(String.t())}
          | {:error, :audit_failed, String.t()}

  @doc """
  Verifies variant claims against source text.

  Accepts options:
    * `:api_url` - Overrides the Gemini API endpoint (essential for Bypass HTTP testing).
    * `:api_key` - Overrides the Gemini API key (defaults to system env).
  """
  @spec verify_grounding(String.t(), String.t(), keyword()) :: grounding_result()
  def verify_grounding(source_text, variant_text, opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("GEMINI_API_KEY")
    api_url = Keyword.get(opts, :api_url) || default_gemini_url(api_key)

    if api_key && api_key != "" do
      execute_remote_audit(source_text, variant_text, api_url)
    else
      execute_offline_heuristic_audit(source_text, variant_text)
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp default_gemini_url(api_key) do
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=#{api_key}"
  end

  defp execute_remote_audit(source_text, variant_text, url) do
    prompt = """
    You are an automated factual grounding auditor.

    SOURCE TEXT (Single Source of Truth):
    #{source_text}

    GENERATED VARIANT TO VERIFY:
    #{variant_text}

    TASK:
    Verify if EVERY factual claim, metric, statistic, or named entity in the VARIANT is directly supported by the SOURCE TEXT.

    Return ONLY a JSON object:
    {
      "is_grounded": true | false,
      "unsupported_claims": ["claim 1", "claim 2"]
    }
    """

    payload = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: %{
        response_mime_type: "application/json",
        temperature: 0.0
      }
    }

    case Req.post(url, json: payload, receive_timeout: 5_000, retry: :safe_transient) do
      {:ok, %{status: 200, body: body}} ->
        parsed_body = parse_body(body)

        case parsed_body do
          %{"candidates" => [%{"content" => %{"parts" => [%{"text" => json_text} | _]}} | _]} ->
            parse_audit_json(json_text)

          _ ->
            {:error, :audit_failed, "Malformed response candidate structure"}
        end

      {:ok, %{status: status}} ->
        {:error, :audit_failed, "Gemini API returned HTTP #{status}"}

      {:error, reason} ->
        {:error, :audit_failed, "Network error during audit: #{inspect(reason)}"}
    end
  end

  defp parse_body(body) when is_binary(body), do: Jason.decode!(body)
  defp parse_body(body) when is_map(body), do: body

  defp parse_audit_json(json_text) do
    case Jason.decode(json_text) do
      {:ok, %{"is_grounded" => true}} ->
        {:ok, :grounded}

      {:ok, %{"is_grounded" => false, "unsupported_claims" => claims}} when is_list(claims) ->
        {:error, :hallucination_detected, claims}

      _ ->
        {:error, :audit_failed, "Invalid JSON structure from auditor"}
    end
  end

  defp execute_offline_heuristic_audit(source_text, variant_text) do
    # Extract numbers/percentages present in variant but missing in source
    variant_numbers = Regex.scan(~r/\b\d+(\.\d+)?%?\b/, variant_text) |> List.flatten()
    source_numbers = Regex.scan(~r/\b\d+(\.\d+)?%?\b/, source_text) |> List.flatten()

    unsupported = Enum.reject(variant_numbers, &(&1 in source_numbers))

    if unsupported != [] do
      {:error, :hallucination_detected,
       ["Variant contains stats/numbers not in source: #{Enum.join(unsupported, ", ")}"]}
    else
      {:ok, :grounded}
    end
  end
end
