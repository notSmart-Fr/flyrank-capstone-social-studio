defmodule FlyrankCapstoneSocialStudio.Content.ConstraintProfile do
  @moduledoc """
  Defines platform-specific constraints and validation logic for content variants.
  """

  @type t :: %__MODULE__{
          platform: String.t(),
          max_length: pos_integer(),
          tone: String.t(),
          max_hashtags: pos_integer()
        }

  defstruct [:platform, :max_length, :tone, :max_hashtags]

  @doc "Retrieves profile struct for a platform string."
  def get(platform), do: Map.get(profiles(), platform)

  @doc "Lists all supported platforms."
  def supported_platforms, do: Map.keys(profiles())

  @doc "Counts hashtags (#) in a text string."
  def count_hashtags(text) when is_binary(text) do
    Regex.scan(~r/#\w+/, text) |> length()
  end

  def count_hashtags(_), do: 0

  # Private function returning the profile map safely
  defp profiles do
    %{
      "telegram" => %__MODULE__{
        platform: "telegram",
        max_length: 2000,
        tone: "Conversational and informative",
        max_hashtags: 5
      },
      "discord" => %__MODULE__{
        platform: "discord",
        max_length: 2000,
        tone: "Conversational, community-oriented, and informative",
        max_hashtags: 5
      },
      "mastodon" => %__MODULE__{
        platform: "mastodon",
        max_length: 2000,
        tone: "Conversational, concise, and authentic",
        max_hashtags: 5
      },
      "mock_x" => %__MODULE__{
        platform: "mock_x",
        max_length: 280,
        tone: "Concise and direct",
        max_hashtags: 2
      },
      "mock_linkedin" => %__MODULE__{
        platform: "mock_linkedin",
        max_length: 3000,
        tone: "Professional and insight-oriented",
        max_hashtags: 5
      }
    }
  end
end
