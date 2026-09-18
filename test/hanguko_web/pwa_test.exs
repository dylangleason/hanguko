defmodule HangukoWeb.PWATest do
  @moduledoc """
  The web app manifest and the icons it names, which are what a phone needs
  to install the app to a home screen.
  """
  use HangukoWeb.ConnCase, async: true

  @manifest Path.join([Application.app_dir(:hanguko, "priv"), "static", "manifest.webmanifest"])

  test "the manifest is served as a manifest", %{conn: conn} do
    conn = get(conn, ~p"/manifest.webmanifest")

    assert response(conn, 200)
    assert ["application/manifest+json" <> _] = get_resp_header(conn, "content-type")
  end

  test "the manifest names the app, a start URL and a display mode" do
    manifest = @manifest |> File.read!() |> Jason.decode!()

    assert manifest["short_name"] == "Hanguko"
    assert manifest["start_url"] == "/"
    assert manifest["display"] == "standalone"
  end

  test "every icon the manifest names is served" do
    manifest = @manifest |> File.read!() |> Jason.decode!()

    assert manifest["icons"] != []

    for %{"src" => src} <- manifest["icons"] do
      assert %{status: 200} = get(Phoenix.ConnTest.build_conn(), src), "#{src} is not served"
    end
  end

  test "the layout links the manifest and the icon a phone home screen uses", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(rel="manifest")
    assert html =~ ~s(rel="apple-touch-icon")
    assert html =~ ~s(name="theme-color")
  end
end
