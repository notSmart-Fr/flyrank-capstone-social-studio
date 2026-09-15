defmodule FlyrankCapstoneSocialStudioWeb.VariantJSON do
  def show(%{variant: variant}) do
    %{
      data: %{
        id: variant.id,
        post_id: variant.post_id,
        platform: variant.platform,
        content: variant.content,
        status: variant.status,
        character_count: variant.character_count,
        hashtags_count: variant.hashtags_count,
        rejection_reason: variant.rejection_reason
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
end
