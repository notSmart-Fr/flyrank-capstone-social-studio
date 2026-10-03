defmodule FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter do
  @behaviour FlyrankCapstoneSocialStudio.Ai.Provider

  @default_gemini_url "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
  @model_name "gemini-2.5-flash"

  # Rates represented as Decimals for exact financial arithmetic
  @input_rate Decimal.new("0.000000075")
  @output_rate Decimal.new("0.00000030")

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

    case Req.post(url, json: payload, receive_timeout: 10_000, retry: :safe_transient) do
      {:ok, %{status: 200, body: body}} ->
        parsed_body = parse_body(body)

        case parsed_body do
          %{"candidates" => [%{"content" => %{"parts" => [%{"text" => json_text} | _]}} | _]} ->
            case Jason.decode(json_text) do
              {:ok, %{"variant_a" => a, "variant_b" => b}} ->
                usage = Map.get(parsed_body, "usageMetadata", %{})
                prompt_tokens = Map.get(usage, "promptTokenCount", 0)
                completion_tokens = Map.get(usage, "candidatesTokenCount", 0)

                total_tokens =
                  Map.get(usage, "totalTokenCount", prompt_tokens + completion_tokens)

                cost = calculate_cost(prompt_tokens, completion_tokens)

                {:ok,
                 %{
                   variant_a: a,
                   variant_b: b,
                   prompt_tokens: prompt_tokens,
                   completion_tokens: completion_tokens,
                   total_tokens: total_tokens,
                   cost: cost,
                   model: @model_name
                 }}

              _ ->
                {:error, "Failed to parse structured JSON from Gemini response"}
            end

          _ ->
            {:error, "Malformed Gemini response structure"}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Gemini API error (HTTP #{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Network request to Gemini failed: #{inspect(reason)}"}
    end
  end

  defp parse_body(body) when is_binary(body), do: Jason.decode!(body)
  defp parse_body(body) when is_map(body), do: body

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
