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
        content: "some content",
        platform: "mock_x",
        rejection_reason: nil,
        status: "draft"
      })
      |> FlyrankCapstoneSocialStudio.Content.create_variant()

    variant
  end
end
