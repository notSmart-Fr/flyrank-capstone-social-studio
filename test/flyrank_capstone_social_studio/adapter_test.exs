defmodule FlyrankCapstoneSocialStudio.AdapterTest do
  use FlyrankCapstoneSocialStudio.DataCase, async: false

  alias FlyrankCapstoneSocialStudio.Publishing
  alias FlyrankCapstoneSocialStudio.Content.AiGenerator

  describe "Adapter Behavior: SocialPublisher implementations" do
    @describetag :publishing
    @describetag :adapters

    test "MockX returns a tweet id and echoes the content" do
      assert {:ok, %{external_id: "x-tweet-" <> _, raw_response: response}} =
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX.publish("Hello X")

      assert response =~ "Hello X"
    end

    test "MockLinkedIn returns a share urn" do
      assert {:ok, %{external_id: "urn:li:share:" <> _}} =
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockLinkedIn.publish("Hello LI")
    end

    @tag :error_handling
    test "mock adapters return an error string when failure is simulated" do
      assert {:error, "Simulated X platform" <> _} =
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX.publish("x",
                 simulate_failure: true
               )

      assert {:error, "Simulated LinkedIn" <> _} =
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockLinkedIn.publish("x",
                 simulate_failure: true
               )
    end

    @tag :error_handling
    test "Telegram returns an explicit error when credentials are missing" do
      env_keys = ["TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID"]
      app_keys = [:telegram_bot_token, :telegram_chat_id]
      saved_env = Map.new(env_keys, &{&1, System.get_env(&1)})

      saved_app =
        Map.new(app_keys, &{&1, Application.get_env(:flyrank_capstone_social_studio, &1)})

      Enum.each(env_keys, &System.delete_env/1)
      Enum.each(app_keys, &Application.delete_env(:flyrank_capstone_social_studio, &1))

      on_exit(fn ->
        Enum.each(saved_env, fn
          {key, nil} -> System.delete_env(key)
          {key, value} -> System.put_env(key, value)
        end)

        Enum.each(saved_app, fn
          {_key, nil} -> :ok
          {key, value} -> Application.put_env(:flyrank_capstone_social_studio, key, value)
        end)
      end)

      assert {:error, message} =
               FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram.publish("Hello")

      assert message =~ "Telegram credentials are missing"
    end
  end

  describe "Telegram HTTP Behavior (Bypass)" do
    @describetag :publishing
    @describetag :adapters
    @describetag :error_handling

    alias FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram

    setup do
      bypass = Bypass.open()
      original_url = Application.get_env(:flyrank_capstone_social_studio, :telegram_base_url)
      saved_env = Map.new(["TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID"], &{&1, System.get_env(&1)})

      Application.put_env(
        :flyrank_capstone_social_studio,
        :telegram_base_url,
        "http://localhost:#{bypass.port}"
      )

      System.put_env("TELEGRAM_BOT_TOKEN", "test-token")
      System.put_env("TELEGRAM_CHAT_ID", "12345")

      on_exit(fn ->
        if original_url do
          Application.put_env(:flyrank_capstone_social_studio, :telegram_base_url, original_url)
        else
          Application.delete_env(:flyrank_capstone_social_studio, :telegram_base_url)
        end

        Enum.each(saved_env, fn
          {key, nil} -> System.delete_env(key)
          {key, value} -> System.put_env(key, value)
        end)
      end)

      %{bypass: bypass}
    end

    test "posts the expected payload and returns the message id", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/bottest-token/sendMessage", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert %{"chat_id" => "12345", "text" => "Hello TG"} = Jason.decode!(body)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{ok: true, result: %{message_id: 42}}))
      end)

      assert {:ok, %{external_id: "42"}} = Telegram.publish("Hello TG")
    end

    test "rate limiting (HTTP 429) is returned as an error", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/bottest-token/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(429, Jason.encode!(%{ok: false, description: "Too Many Requests"}))
      end)

      assert {:error, "Telegram API HTTP 429" <> _} = Telegram.publish("Hello TG")
    end

    test "rate limiting (HTTP 429) parses Retry-After header and returns rate_limited tuple", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, "POST", "/bottest-token/sendMessage", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "45")
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(429, Jason.encode!(%{ok: false, description: "Too Many Requests"}))
      end)

      assert {:error, {:rate_limited, 45}} = Telegram.publish("Hello TG")
    end

    test "a network failure is returned as an error", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, "Network failure" <> _} = Telegram.publish("Hello TG")
    end
  end

  describe "Publishing Adapter Seam" do
    @describetag :publishing
    @describetag :adapters

    test "adapter_for_platform/1 resolves correct modules from application config" do
      assert Publishing.adapter_for_platform("telegram") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.Telegram

      assert Publishing.adapter_for_platform("mock_x") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX

      assert Publishing.adapter_for_platform("mock_linkedin") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockLinkedIn
    end

    test "dynamic configuration swap changes dispatch target without modifying business logic" do
      original_config = Application.get_env(:flyrank_capstone_social_studio, :adapters)

      swapped_config =
        Keyword.put(
          original_config,
          :telegram,
          FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX
        )

      Application.put_env(:flyrank_capstone_social_studio, :adapters, swapped_config)

      assert Publishing.adapter_for_platform("telegram") ==
               FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX

      Application.put_env(:flyrank_capstone_social_studio, :adapters, original_config)
    end
  end

  # ===========================================================================
  # AI Provider Adapter Seam Tests
  # ===========================================================================
  describe "AI Provider Adapter Seam" do
    @describetag :adapters
    @describetag :ai_generation
    test "AiGenerator resolves configured default AI adapter" do
      configured_adapter = Application.get_env(:flyrank_capstone_social_studio, :ai_adapter)

      assert configured_adapter == FlyrankCapstoneSocialStudio.Ai.Adapters.GeminiAdapter
    end

    test "dynamic AI adapter swap changes generation target without modifying business logic" do
      original_ai_adapter = Application.get_env(:flyrank_capstone_social_studio, :ai_adapter)

      # Update TestMockAiAdapter to accept optional _opts \\ [] as 4th parameter
      defmodule TestMockAiAdapter do
        @behaviour FlyrankCapstoneSocialStudio.Ai.Provider

        @impl true
        def generate_ab_variants(_content, _platform, _profile, _opts \\ []) do
          {:ok,
           %{
             variant_a: "Swapped Mock Variant A",
             variant_b: "Swapped Mock Variant B",
             prompt_tokens: 10,
             completion_tokens: 10,
             total_tokens: 20,
             cost: Decimal.new("0.0"),
             model: "swapped-mock-ai"
           }}
        end
      end

      try do
        Application.put_env(:flyrank_capstone_social_studio, :ai_adapter, TestMockAiAdapter)

        assert {:ok, result} =
                 AiGenerator.generate_ab_variants("Sample text", "telegram", %{
                   max_length: 280,
                   max_hashtags: 2,
                   tone: "professional"
                 })

        assert result.variant_a == "Swapped Mock Variant A"
        assert result.model == "swapped-mock-ai"
      after
        Application.put_env(:flyrank_capstone_social_studio, :ai_adapter, original_ai_adapter)
      end
    end
  end
end
