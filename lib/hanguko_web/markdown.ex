defmodule HangukoWeb.Markdown do
  @moduledoc """
  Renders the markdown used in grammar explanations.

  Raw HTML in the source is dropped rather than passed through, so a content
  pack can never inject markup into a page.
  """

  @doc """
  Renders `markdown` as safe HTML. Returns an empty result for `nil`, so a
  point without an explanation renders as nothing.
  """
  def to_html(nil), do: {:safe, ""}

  def to_html(markdown) when is_binary(markdown) do
    case MDEx.to_html(markdown) do
      {:ok, html} -> {:safe, html}
      {:error, _} -> {:safe, ""}
    end
  end
end
