defmodule FlyrankCapstoneSocialStudio.Content.ConstraintProfile do
  @moduledoc """
  Defines platform-specific constraints and validation logic for content variants.
  """

  @type t :: %__MODULE__{
          platform: String.t(),
          max_length: pos_integer(),
          tone: String.t(),
          max_hashtags: pos_integer(),
          parse_mode: String.t() | nil
        }

  defstruct [:platform, :max_length, :tone, :max_hashtags, :parse_mode]

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
        max_length: 4096,
        tone: "Conversational and informative",
        max_hashtags: 5,
        parse_mode: "HTML"
      },
      "discord" => %__MODULE__{
        platform: "discord",
        max_length: 2000,
        tone: "Conversational, community-oriented, and informative",
        max_hashtags: 5,
        parse_mode: "Markdown"
      },
      "mastodon" => %__MODULE__{
        platform: "mastodon",
        max_length: 2000,
        tone: "Conversational, concise, and authentic",
        max_hashtags: 5,
        parse_mode: nil
      },
      "mock_x" => %__MODULE__{
        platform: "mock_x",
        max_length: 280,
        tone: "Concise and direct",
        max_hashtags: 2,
        parse_mode: nil
      },
      "mock_linkedin" => %__MODULE__{
        platform: "mock_linkedin",
        max_length: 3000,
        tone: "Professional and insight-oriented",
        max_hashtags: 5,
        parse_mode: nil
      }
    }
  end
end
