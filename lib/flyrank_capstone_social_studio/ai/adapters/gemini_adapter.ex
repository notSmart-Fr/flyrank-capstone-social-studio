defmodule FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter do
  @moduledoc """
  Gemini API provider adapter for generating A/B social media post variants and telemetry tracking.

  Implements the `FlyrankCapstoneSocialStudio.Ai.Provider` behaviour to interface with the
  Google Gemini API (`gemini-2.5-flash`). Handles prompt construction based on platform
  constraints, structured JSON response parsing, token accounting via exact `Decimal` arithmetic,
  and fallback content generation.

  ## Configuration & Credentials

  The adapter requires a valid Gemini API key, resolved in the following precedence:
    1. Explicit `:api_key` option passed to `generate_ab_variants/4`.
    2. `GEMINI_API_KEY` OS environment variable.
    3. Application environment key `:gemini_api_key` under `:flyrank_capstone_social_studio`.

  If no valid API key is present, the adapter automatically degrades gracefully to an offline mock generator.

  ## Financial Telemetry

  Token usage costs are computed with `Decimal` precision to avoid floating-point loss:
  * **Input Tokens:** `$0.000000075` per token (`$0.075 / 1M`).
  * **Output Tokens:** `$0.00000030` per token (`$0.30 / 1M`).
  """

  @behaviour FlyrankCapstoneSocialStudio.Ai.Provider

  @type content :: String.t()
  @type platform_name :: String.t()
  @type profile :: struct()
  @type option :: {:api_key, String.t()} | {:api_url, String.t()}
  @type options :: [option()]

  @type telemetry_payload :: %{
          variant_a: String.t(),
          variant_b: String.t(),
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          cost: Decimal.t(),
          model: String.t()
        }

  @type fallback_payload :: %{
          variant_a: String.t(),
          variant_b: String.t(),
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          cost: Decimal.t(),
          model: String.t()
        }

  @default_gemini_url "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
  @model_name "gemini-2.5-flash"

  @input_rate Decimal.new("0.000000075")
  @output_rate Decimal.new("0.00000030")

  @doc """
  Generates two distinct A/B social media post variants (`variant_a` and `variant_b`)
  tailored to a specific platform profile and returns model telemetry.

  ## Parameters

    * `content` - The source text or blog post summary to generate variants from.
    * `platform_name` - Target platform identifier (e.g., `"telegram"`, `"mock_x"`, `"mock_linkedin"`).
    * `profile` - Constraint profile struct containing `:max_length`, `:max_hashtags`, and `:tone`.
    * `opts` - Keyword list of optional overrides (`:api_key`, `:api_url`).

  ## Return Values

    * `{:ok, telemetry_payload}` - Successful generation and JSON parsing with token cost telemetry.
    * `{:error, String.t()}` - Detailed failure message for API HTTP errors, network timeouts, or malformed JSON payloads.

  ## Examples

      iex> profile = %{max_length: 280, max_hashtags: 3, tone: "professional"}
      iex> GeminiAdapter.generate_ab_variants("Elixir 1.18 Released!", "mock_x", profile)
      {:ok,
       %{
         variant_a: "📌 [Variant A]: Elixir 1.18 Released!...",
         variant_b: "💡 [Variant B]: Deep dive on: Elixir 1.18...",
         prompt_tokens: 120,
         completion_tokens: 45,
         total_tokens: 165,
         cost: #Decimal<0.00002250>,
         model: "gemini-2.5-flash"
       }}

      iex> GeminiAdapter.generate_ab_variants("Text", "mock_x", profile, api_key: nil)
      {:ok, %{model: "fallback-mock", cost: #Decimal<0.0>, ...}}
  """
  @impl true
  def generate_ab_variants(content, platform_name, profile, opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || gemini_api_key()
    api_url = Keyword.get(opts, :api_url) || default_url(api_key)

    if api_key && api_key != "" do
      call_gemini_api(content, platform_name, profile, api_url)
    else
      generate_fallback_ab(content, profile)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp default_url(api_key) do
    "#{@default_gemini_url}?key=#{api_key}"
  end

  defp gemini_api_key do
    System.get_env("GEMINI_API_KEY") ||
      Application.get_env(:flyrank_capstone_social_studio, :gemini_api_key)
  end

  defp call_gemini_api(content, platform_name, profile, url) do
    prompt = """
    You are a social media strategist.
    Create TWO distinct variants (Variant A and Variant B) for the post on platform: #{platform_name}.

    STRICT CONSTRAINTS:
    - Maximum character length per variant: #{profile.max_length}
    - Maximum hashtag count: #{profile.max_hashtags}
    - Tone: #{profile.tone}

    STYLING RULES:
    - Variant A: Direct, punchy, bold hook.
    - Variant B: Storytelling, analytical, key takeaways.

    SOURCE TEXT:
    #{content}

    Return ONLY a raw JSON object with keys "variant_a" and "variant_b".
    """

    payload = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: %{
        response_mime_type: "application/json",
        temperature: 0.2
      }
    }

    with {:ok, %{status: 200, body: raw_body}} <- post_gemini_api(url, payload),
         {:ok, parsed_body} <- safely_parse_body(raw_body),
         {:ok, json_text} <- extract_candidate_text(parsed_body),
         {:ok, variants} <- parse_variants_json(json_text) do
      {:ok, build_telemetry_payload(parsed_body, variants)}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, "Gemini API error (HTTP #{status}): #{inspect(body)}"}

      {:error, :malformed_structure} ->
        {:error, "Malformed Gemini response structure"}

      {:error, :json_decode_failed} ->
        {:error, "Failed to parse structured JSON from Gemini response"}

      {:error, reason} ->
        {:error, "Network request to Gemini failed: #{inspect(reason)}"}
    end
  end

  # --- Private Helper Functions ---

  defp post_gemini_api(url, payload) do
    Req.post(url, json: payload, receive_timeout: 10_000, retry: :safe_transient)
  end

  defp safely_parse_body(body) when is_map(body), do: {:ok, body}

  defp safely_parse_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      _error -> {:error, :malformed_structure}
    end
  end

  defp safely_parse_body(_body), do: {:error, :malformed_structure}

  defp extract_candidate_text(%{
         "candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]
       }) do
    {:ok, text}
  end

  defp extract_candidate_text(_parsed_body), do: {:error, :malformed_structure}

  defp parse_variants_json(json_text) do
    case Jason.decode(json_text) do
      {:ok, %{"variant_a" => a, "variant_b" => b}} when is_binary(a) and is_binary(b) ->
        {:ok, {a, b}}

      _ ->
        {:error, :json_decode_failed}
    end
  end

  defp build_telemetry_payload(parsed_body, {variant_a, variant_b}) do
    usage = Map.get(parsed_body, "usageMetadata", %{})
    prompt_tokens = Map.get(usage, "promptTokenCount", 0)
    completion_tokens = Map.get(usage, "candidatesTokenCount", 0)
    total_tokens = Map.get(usage, "totalTokenCount", prompt_tokens + completion_tokens)
    cost = calculate_cost(prompt_tokens, completion_tokens)

    %{
      variant_a: variant_a,
      variant_b: variant_b,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      cost: cost,
      model: @model_name
    }
  end

  # Calculates token costs using Decimal math to avoid float precision loss
  defp calculate_cost(prompt_tokens, completion_tokens) do
    input_cost = Decimal.mult(Decimal.new(prompt_tokens), @input_rate)
    output_cost = Decimal.mult(Decimal.new(completion_tokens), @output_rate)
    Decimal.add(input_cost, output_cost)
  end

  defp generate_fallback_ab(content, profile) do
    max_len = max(profile.max_length - 30, 1)
    base_text = String.slice(content, 0, max_len)

    {:ok,
     %{
       variant_a: "📌 [Variant A]: #{base_text} #tech",
       variant_b: "💡 [Variant B]: Deep dive on: #{base_text} #tech #news",
       prompt_tokens: 0,
       completion_tokens: 0,
       total_tokens: 0,
       cost: Decimal.new("0.0"),
       model: "fallback-mock"
     }}
  end
end
