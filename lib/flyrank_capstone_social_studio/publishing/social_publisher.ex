defmodule FlyrankCapstoneSocialStudio.Publishing.SocialPublisher do
  @moduledoc """
  Behaviour implemented by social platform publishing adapters.
  """

  @callback publish(String.t(), keyword()) ::
              {:ok, %{external_id: String.t(), raw_response: String.t()}}
              | {:error, term()}
end
