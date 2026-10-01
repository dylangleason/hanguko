defmodule HangukoWeb.AudioServingTest do
  @moduledoc """
  The endpoint serving generated clips out of the configured storage
  directory. In production that directory is a mounted volume, outside the
  release entirely, so the `Plug.Static` that serves `priv/static` can't reach
  it - see `Hanguko.Audio.Storage.Local`.
  """
  use HangukoWeb.ConnCase, async: true

  alias Hanguko.Audio.Storage.Local

  @data "not an mp3, but bytes all the same"

  setup do
    path = "te/st/#{System.unique_integer([:positive])}.mp3"
    :ok = Local.put(path, @data, "audio/mpeg")

    on_exit(fn -> path |> Local.full_path() |> File.rm_rf!() end)

    %{path: path, url: Local.url(path)}
  end

  test "serves a clip at the URL storage derives for it", %{conn: conn, url: url} do
    assert @data == conn |> get(url) |> response(200)
  end

  test "serves a clip as audio", %{conn: conn, url: url} do
    conn = get(conn, url)

    assert ["audio/mpeg" <> _] = get_resp_header(conn, "content-type")
  end

  test "tells the browser a clip never changes", %{conn: conn, url: url} do
    conn = get(conn, url)

    assert ["public, max-age=31536000, immutable"] = get_resp_header(conn, "cache-control")
  end

  test "answers a revalidation with 304 and no body", %{conn: conn, url: url} do
    [etag] = conn |> get(url) |> get_resp_header("etag")

    conn = build_conn() |> put_req_header("if-none-match", etag) |> get(url)

    assert "" == response(conn, 304)
  end

  test "answers 404 for a path with no clip", %{conn: conn} do
    # Falls through to the rest of the pipeline rather than erroring, so a clip
    # whose file is missing degrades to the browser's own speech.
    assert 404 == get(conn, "/audio/no/su/chclip.mp3").status
  end

  test "refuses a path that climbs out of the storage directory", %{conn: conn} do
    assert_error_sent 400, fn -> get(conn, "/audio/../../mix.exs") end
  end
end
