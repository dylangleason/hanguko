defmodule HangukoWeb.AudioHookTest do
  @moduledoc """
  The `audio:speak` event, which the `Speak` JS hook pushes for a button with
  no pre-generated clip, and which `HangukoWeb.AudioHook` answers on behalf of
  every LiveView.

  Every reply has to be a value the client can be handed: a reason that isn't
  JSON-encodable would take the LiveView down rather than fall back to browser
  speech, which is the opposite of the point.
  """
  # Swapping the configured provider is global, so this file can't run
  # alongside anything else.
  use HangukoWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Hanguko.ContentFixtures

  alias Hanguko.Audio
  alias Hanguko.Audio.Storage.Local
  alias Hanguko.Fakes.AudioProvider, as: Fake

  @text "안녕하세요"

  setup do
    on_exit(fn ->
      @text
      |> Audio.clip_key()
      |> Audio.storage_path("audio/mpeg")
      |> Local.full_path()
      |> File.rm_rf!()
    end)

    :ok
  end

  describe "audio:speak" do
    setup :register_and_log_in_user

    test "replies with the URL of the clip it synthesized", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      render_hook(view, "audio:speak", %{"text" => @text})

      assert_reply view, %{url: url}
      assert url =~ "/audio/"
      assert_received {Fake, :synthesize, @text, "test-voice"}
    end

    test "replays a stored clip rather than buying it again", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      render_hook(view, "audio:speak", %{"text" => @text})
      assert_reply view, %{url: url}
      assert_received {Fake, :synthesize, @text, _}

      render_hook(view, "audio:speak", %{"text" => @text})

      assert_reply view, %{url: ^url}
      refute_received {Fake, :synthesize, _, _}
    end

    test "reports a text it won't synthesize", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      render_hook(view, "audio:speak", %{"text" => "hello"})

      assert_reply view, %{error: "invalid_text"}
      refute_received {Fake, :synthesize, _, _}
    end

    test "reports a request carrying no text at all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      render_hook(view, "audio:speak", %{})

      assert_reply view, %{error: "invalid_text"}
    end

    test "reports audio being switched off", %{conn: conn} do
      put_audio_env(:provider, nil)
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      render_hook(view, "audio:speak", %{"text" => @text})

      assert_reply view, %{error: "disabled"}
    end

    test "logs a provider failure and reports it as one word", %{conn: conn} do
      put_audio_env(:provider, Hanguko.Fakes.FailingAudioProvider)
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      log = capture_log(fn -> render_hook(view, "audio:speak", %{"text" => @text}) end)

      assert_reply view, %{error: "unavailable"}
      assert log =~ "synthesis_failed"
    end

    test "leaves a page's own events to the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      view |> element("#picker-initial button[phx-value-jamo='ㄴ']") |> render_click()

      assert has_element?(view, "#builder-syllable", "난")
    end
  end

  test "refuses a visitor who isn't signed in", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hangeul")

    render_hook(view, "audio:speak", %{"text" => @text})

    assert_reply view, %{error: "unauthenticated"}
    refute_received {Fake, :synthesize, _, _}
  end

  # One page per live_session in the router: the hook is attached there, not in
  # the LiveViews, so a session it was left out of answers nothing and takes
  # the page down the first time someone presses a speak button.
  describe "every live session" do
    setup :register_and_log_in_user

    test "answers on a public curriculum page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/hangeul")

      render_hook(view, "audio:speak", %{"text" => @text})

      assert_reply view, %{url: _}
    end

    test "answers on a page that requires a login", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cards")

      render_hook(view, "audio:speak", %{"text" => @text})

      assert_reply view, %{url: _}
    end

    test "answers on a studying page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "audio:speak", %{"text" => @text})

      assert_reply view, %{url: _}
    end
  end

  # Whether a page may offer server synthesis at all is decided once on mount,
  # for every page in one place, because getting it wrong either wastes a round
  # trip per button or silently downgrades every learner to browser speech.
  describe "offering server synthesis" do
    setup do
      deck = deck_fixture(kind: :phrases, slug: "audio-hook-phrases")

      %{item: item_fixture(deck, korean: @text, kind: :phrase), deck: deck}
    end

    test "offers it to a signed-in learner", %{conn: conn, deck: deck, item: item} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      {:ok, view, _html} = live(conn, ~p"/decks/#{deck.slug}")

      assert has_element?(view, "#items-#{item.id}-speak[data-remote='true']")
    end

    test "withholds it from a visitor who isn't signed in", %{
      conn: conn,
      deck: deck,
      item: item
    } do
      {:ok, view, _html} = live(conn, ~p"/decks/#{deck.slug}")

      refute has_element?(view, "#items-#{item.id}-speak[data-remote]")
    end

    test "withholds it when audio is switched off", %{conn: conn, deck: deck, item: item} do
      put_audio_env(:provider, nil)
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      {:ok, view, _html} = live(conn, ~p"/decks/#{deck.slug}")

      refute has_element?(view, "#items-#{item.id}-speak[data-remote]")
    end
  end

  defp put_audio_env(key, value) do
    audio = Application.fetch_env!(:hanguko, Hanguko.Audio)
    Application.put_env(:hanguko, Hanguko.Audio, Keyword.put(audio, key, value))
    on_exit(fn -> Application.put_env(:hanguko, Hanguko.Audio, audio) end)
  end
end
