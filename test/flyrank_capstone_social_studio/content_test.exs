defmodule FlyrankCapstoneSocialStudio.ContentTest do
  use FlyrankCapstoneSocialStudio.DataCase

  alias FlyrankCapstoneSocialStudio.Content

  describe "posts" do
    alias FlyrankCapstoneSocialStudio.Content.Post

    import FlyrankCapstoneSocialStudio.ContentFixtures

    @invalid_attrs %{title: nil, url: nil, source_type: nil, content: nil, external_source_id: nil}

    test "list_posts/0 returns all posts" do
      post = post_fixture()
      assert Content.list_posts() == [post]
    end

    test "get_post!/1 returns the post with given id" do
      post = post_fixture()
      assert Content.get_post!(post.id) == post
    end

    test "create_post/1 with valid data creates a post" do
      valid_attrs = %{title: "some title", url: "some url", source_type: "some source_type", content: "some content", external_source_id: "some external_source_id"}

      assert {:ok, %Post{} = post} = Content.create_post(valid_attrs)
      assert post.title == "some title"
      assert post.url == "some url"
      assert post.source_type == "some source_type"
      assert post.content == "some content"
      assert post.external_source_id == "some external_source_id"
    end

    test "create_post/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Content.create_post(@invalid_attrs)
    end

    test "update_post/2 with valid data updates the post" do
      post = post_fixture()
      update_attrs = %{title: "some updated title", url: "some updated url", source_type: "some updated source_type", content: "some updated content", external_source_id: "some updated external_source_id"}

      assert {:ok, %Post{} = post} = Content.update_post(post, update_attrs)
      assert post.title == "some updated title"
      assert post.url == "some updated url"
      assert post.source_type == "some updated source_type"
      assert post.content == "some updated content"
      assert post.external_source_id == "some updated external_source_id"
    end

    test "update_post/2 with invalid data returns error changeset" do
      post = post_fixture()
      assert {:error, %Ecto.Changeset{}} = Content.update_post(post, @invalid_attrs)
      assert post == Content.get_post!(post.id)
    end

    test "delete_post/1 deletes the post" do
      post = post_fixture()
      assert {:ok, %Post{}} = Content.delete_post(post)
      assert_raise Ecto.NoResultsError, fn -> Content.get_post!(post.id) end
    end

    test "change_post/1 returns a post changeset" do
      post = post_fixture()
      assert %Ecto.Changeset{} = Content.change_post(post)
    end
  end

  describe "variants" do
    alias FlyrankCapstoneSocialStudio.Content.Variant

    import FlyrankCapstoneSocialStudio.ContentFixtures

    @invalid_attrs %{status: nil, platform: nil, content: nil, hashtags_count: nil, character_count: nil, rejection_reason: nil}

    test "list_variants/0 returns all variants" do
      variant = variant_fixture()
      assert Content.list_variants() == [variant]
    end

    test "get_variant!/1 returns the variant with given id" do
      variant = variant_fixture()
      assert Content.get_variant!(variant.id) == variant
    end

    test "create_variant/1 with valid data creates a variant" do
      valid_attrs = %{status: "some status", platform: "some platform", content: "some content", hashtags_count: 42, character_count: 42, rejection_reason: "some rejection_reason"}

      assert {:ok, %Variant{} = variant} = Content.create_variant(valid_attrs)
      assert variant.status == "some status"
      assert variant.platform == "some platform"
      assert variant.content == "some content"
      assert variant.hashtags_count == 42
      assert variant.character_count == 42
      assert variant.rejection_reason == "some rejection_reason"
    end

    test "create_variant/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Content.create_variant(@invalid_attrs)
    end

    test "update_variant/2 with valid data updates the variant" do
      variant = variant_fixture()
      update_attrs = %{status: "some updated status", platform: "some updated platform", content: "some updated content", hashtags_count: 43, character_count: 43, rejection_reason: "some updated rejection_reason"}

      assert {:ok, %Variant{} = variant} = Content.update_variant(variant, update_attrs)
      assert variant.status == "some updated status"
      assert variant.platform == "some updated platform"
      assert variant.content == "some updated content"
      assert variant.hashtags_count == 43
      assert variant.character_count == 43
      assert variant.rejection_reason == "some updated rejection_reason"
    end

    test "update_variant/2 with invalid data returns error changeset" do
      variant = variant_fixture()
      assert {:error, %Ecto.Changeset{}} = Content.update_variant(variant, @invalid_attrs)
      assert variant == Content.get_variant!(variant.id)
    end

    test "delete_variant/1 deletes the variant" do
      variant = variant_fixture()
      assert {:ok, %Variant{}} = Content.delete_variant(variant)
      assert_raise Ecto.NoResultsError, fn -> Content.get_variant!(variant.id) end
    end

    test "change_variant/1 returns a variant changeset" do
      variant = variant_fixture()
      assert %Ecto.Changeset{} = Content.change_variant(variant)
    end
  end
end
