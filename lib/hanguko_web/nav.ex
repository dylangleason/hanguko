defmodule HangukoWeb.Nav do
  @moduledoc """
  Tells the layout which page is showing, so the main nav can mark its
  section as current.

  Every LiveView mounts this hook (see `HangukoWeb.live_view/0`). It keeps
  `@current_path` up to date on each `handle_params`, which covers live
  navigation and patches as well as the first render, and LiveViews pass it
  on as `<Layouts.app current_path={@current_path}>`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, nil)
      |> attach_hook(:current_path, :handle_params, fn _params, url, socket ->
        {:cont, assign(socket, :current_path, URI.parse(url).path)}
      end)

    {:cont, socket}
  end
end
