defmodule FlyrankCapstoneSocialStudioWeb.PostJSON do
  alias FlyrankCapstoneSocialStudio.Content.Variant

  def show_with_variants(%{post: post, variants: variants}) do
    %{
      data: %{
        id: post.id,
        title: post.title,
        source_type: post.source_type,
        content: post.content,
        url: post.url,
        external_source_id: post.external_source_id,
        inserted_at: post.inserted_at,
        variants: Enum.map(variants, &variant_data/1)
      }
    }
  end

  def error(%{changeset: changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    %{errors: errors}
  end

  defp variant_data(%Variant{} = variant) do
    %{
      id: variant.id,
      post_id: variant.post_id,
      platform: variant.platform,
      content: variant.content,
      status: variant.status,
      character_count: variant.character_count,
      hashtags_count: variant.hashtags_count
    }
  end
end
