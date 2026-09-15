defmodule FlyrankCapstoneSocialStudio.Publishing.Adapters.MockLinkedIn do
  @behaviour FlyrankCapstoneSocialStudio.Publishing.SocialPublisher

  @impl true
  def publish(content, opts \\ []) do
    should_fail? = Keyword.get(opts, :simulate_failure, false)

    if should_fail? do
      {:error, "Simulated LinkedIn API 500 internal server error"}
    else
      external_id = "urn:li:share:#{:erlang.unique_integer([:positive])}"
      {:ok, %{external_id: external_id, raw_response: "Mock LinkedIn post published: #{String.slice(content, 0, 30)}..."}}
    end
  end
end
