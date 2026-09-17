defmodule HangukoWeb.DetectTimezone do
  @moduledoc """
  Loads the scope's study settings, first detecting the browser's time zone
  if the scope doesn't already have one on record.

  Attached via the router's `on_mount` list to the `live_session` for pages
  that read study settings on mount (dashboard, study, stats), so the
  settings row is fetched once and shared instead of each page detecting the
  time zone and loading the row again itself. It must be listed after
  `{HangukoWeb.UserAuth, :require_authenticated}`, which is what assigns
  `current_scope`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1]

  alias Hanguko.SRS

  def on_mount(:default, _params, _session, socket) do
    scope = socket.assigns.current_scope

    settings =
      if connected?(socket),
        do: SRS.put_detected_timezone(scope, get_connect_params(socket)["timezone"]),
        else: SRS.get_settings(scope)

    {:cont, assign(socket, :settings, settings)}
  end
end
