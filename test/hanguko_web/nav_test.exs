defmodule HangukoWeb.NavTest do
  use HangukoWeb.ConnCase, async: true

  # A LiveView rendered outside the router, as `live_render/3` or
  # `live_isolated/3` would render it.
  defmodule EmbeddedLive do
    use HangukoWeb, :live_view

    def render(assigns) do
      ~H"""
      <p id="embedded">path: {inspect(@current_path)}</p>
      """
    end
  end

  test "a LiveView not mounted by the router still mounts, with no current path", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, EmbeddedLive)

    assert has_element?(view, "#embedded", "path: nil")
  end
end
