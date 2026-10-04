defmodule FlyrankCapstoneSocialStudio.Test.CrashingPublisher do
  @moduledoc """
  Test-only publishing adapter that raises instead of returning an error tuple.
  """
  @behaviour FlyrankCapstoneSocialStudio.Publishing.SocialPublisher

  @impl true
  def publish(_content, _opts \\ []), do: raise("boom from adapter")
end
