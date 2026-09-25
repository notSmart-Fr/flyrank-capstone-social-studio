defmodule FlyrankCapstoneSocialStudio.Publishing.Adapters.MockX do
  @behaviour FlyrankCapstoneSocialStudio.Publishing.SocialPublisher

  @impl true
  @spec publish(any()) ::
          {:error, <<_::416>>}
          | {:ok, %{external_id: <<_::64, _::_*8>>, raw_response: <<_::64, _::_*8>>}}
  def publish(content, opts \\ []) do
    should_fail? = Keyword.get(opts, :simulate_failure, false)

    if should_fail? do
      {:error, "Simulated X platform rate limit / connection timeout"}
    else
      external_id = "x-tweet-#{:erlang.unique_integer([:positive])}"

      {:ok,
       %{
         external_id: external_id,
         raw_response: "Mock X tweet published: #{String.slice(content, 0, 30)}..."
       }}
    end
  end
end
