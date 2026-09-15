defmodule HangukoWeb.Nav do
  @moduledoc """
  Tells the layout which page is showing, so the main nav can mark its
  section as current.

  Every LiveView mounts this hook (see `HangukoWeb.live_view/0`). It keeps
  `@current_path` up to date on each `handle_params`, which covers live
  navigation and patches as well as the first render, and LiveViews pass it
  on as `<Layouts.app current_path={@current_path}>`.

  LiveView only allows `handle_params` hooks on views mounted by the router,
  so a view rendered some other way (`live_render/3`, or `live_isolated/3`
  in tests) gets `@current_path` set to `nil` and no hook. Such a view isn't
  a page of its own, so there is no section to mark.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, _params, _session, socket) do
    socket = assign(socket, :current_path, nil)

    if socket.router do
      {:cont, attach_hook(socket, :current_path, :handle_params, &put_current_path/3)}
    else
      {:cont, socket}
    end
  end

  defp put_current_path(_params, url, socket) do
    {:cont, assign(socket, :current_path, URI.parse(url).path)}
  end
end
