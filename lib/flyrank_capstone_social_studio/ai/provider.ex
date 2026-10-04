defmodule FlyrankCapstoneSocialStudio.Ai.Provider do
  @moduledoc """
  Behaviour for AI content generation adapters.
  """

  @doc """
  Behaviour for AI content generation adapters.
  """
  @callback generate_ab_variants(
              content :: String.t(),
              platform_name :: String.t(),
              profile :: map(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, term()}
end
