defmodule FlyrankCapstoneSocialStudio.Test.FailingPublisher do
  @moduledoc """
  Test-only publishing adapter that always fails, used to exercise failure
  handling in the dispatcher, worker and UI action without simulating options.
  """
  @behaviour FlyrankCapstoneSocialStudio.Publishing.SocialPublisher

  @impl true
  def publish(_content, _opts \\ []), do: {:error, "Simulated adapter outage"}

  @doc """
  Swaps the configured adapter for `platform` and restores it when the test exits.
  """
  @spec swap_adapter!(atom(), module()) :: :ok
  def swap_adapter!(platform, adapter) do
    original = Application.get_env(:flyrank_capstone_social_studio, :adapters)

    Application.put_env(
      :flyrank_capstone_social_studio,
      :adapters,
      Keyword.put(original, platform, adapter)
    )

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:flyrank_capstone_social_studio, :adapters, original)
    end)
  end
end
