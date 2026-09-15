defmodule FlyrankCapstoneSocialStudio.Publishing.SocialPublisher do
  @callback publish(String.t(), keyword()) ::
              {:ok, %{external_id: String.t(), raw_response: String.t()}}
              | {:error, term()}
end
