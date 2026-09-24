defmodule FlyrankCapstoneSocialStudioWeb.PostLive.Queries.PostQuery do
  @moduledoc """
  Encapsulates data fetching, variant selection, and Oban job status queries.
  """
  import Ecto.Query

  alias FlyrankCapstoneSocialStudio.Content
  alias FlyrankCapstoneSocialStudio.Repo

  def get_post_details(id) do
    Content.get_campaign_details(id) || Content.get_post!(id)
  end

  def find_variant_for_platform(variants, platform) do
    platform_variants = Enum.filter(variants || [], &(Map.get(&1, :platform) == platform))

    ai_variant =
      platform_variants
      |> Enum.filter(fn v ->
        model = Map.get(v, :model_used)
        model && model != "Local Constraint Template"
      end)
      |> List.last()

    ai_variant || List.last(platform_variants)
  end

  def oban_generating?(post_id, platform) do
    query =
      from job in Oban.Job,
        where: job.queue == "default",
        where: fragment("args->>'post_id' = ?", ^to_string(post_id)),
        where: fragment("args->>'platform' = ?", ^to_string(platform)),
        where: job.state in ["available", "executing", "retryable"]

    Repo.exists?(query)
  end

  def has_ai_variant?(variants, platform) do
    (variants || [])
    |> Enum.filter(&(Map.get(&1, :platform) == platform))
    |> Enum.any?(fn v ->
      model = Map.get(v, :model_used)
      model && model != "Local Constraint Template"
    end)
  end
end
