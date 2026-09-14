defmodule FlyrankCapstoneSocialStudio.ContentFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FlyrankCapstoneSocialStudio.Content` context.
  """

  @doc """
  Generate a post.
  """
  def post_fixture(attrs \\ %{}) do
    {:ok, post} =
      attrs
      |> Enum.into(%{
        content: "some content",
        external_source_id: "some external_source_id",
        source_type: "some source_type",
        title: "some title",
        url: "some url"
      })
      |> FlyrankCapstoneSocialStudio.Content.create_post()

    post
  end

  @doc """
  Generate a variant.
  """
  def variant_fixture(attrs \\ %{}) do
    {:ok, variant} =
      attrs
      |> Enum.into(%{
        character_count: 42,
        content: "some content",
        hashtags_count: 42,
        platform: "some platform",
        rejection_reason: "some rejection_reason",
        status: "some status"
      })
      |> FlyrankCapstoneSocialStudio.Content.create_variant()

    variant
  end
end
