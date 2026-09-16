defmodule FlyrankCapstoneSocialStudio.Content.AiGenerator do
  @moduledoc """
  Generates platform-specific A/B post drafts using the Gemini API.
  """

  @gemini_url "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

  @doc """
  Generates Variant A (Direct/Hook) and Variant B (Story/Analytical) for a target platform.
  """
  def generate_ab_variants(content, platform_name, profile) do
    api_key = System.get_env("GEMINI_API_KEY")

    if api_key && api_key != "" do
      call_gemini_api(content, platform_name, profile, api_key)
    else
      generate_fallback_ab(content, profile)
    end
  end

  defp call_gemini_api(content, platform_name, profile, api_key) do
    url = "#{@gemini_url}?key=#{api_key}"

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
        response_mime_type: "application/json"
      }
    }

    case Req.post(url, json: payload) do
      {:ok, %{status: 200, body: %{"candidates" => [%{"content" => %{"parts" => [%{"text" => json_text} | _]}} | _]}}} ->
        case Jason.decode(json_text) do
          {:ok, %{"variant_a" => a, "variant_b" => b}} ->
            {:ok, %{variant_a: a, variant_b: b}}

          _ ->
            {:error, "Failed to parse structured JSON from Gemini response"}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Gemini API error (HTTP #{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Network request to Gemini failed: #{inspect(reason)}"}
    end
  end

  # Fallback generator for offline/local test execution
  defp generate_fallback_ab(content, profile) do
    max_len = max(profile.max_length - 30, 1)
    base_text = String.slice(content, 0, max_len)

    {:ok,
     %{
       variant_a: "📌 [Variant A]: #{base_text} #tech",
       variant_b: "💡 [Variant B]: Deep dive on: #{base_text} #tech #news"
     }}
  end
end
