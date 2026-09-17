defmodule FlyrankCapstoneSocialStudio.Ai.Provider do
  @doc """
  Contract for generating A/B platform variants.
  """
  @callback generate_ab_variants(content :: String.t(), platform :: String.t(), profile :: map()) ::
              {:ok, map()} | {:error, term()}
end
