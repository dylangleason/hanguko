defmodule HangukoWeb.KoreanComponentsTest do
  @moduledoc """
  The `speak_button` markup, which is the whole contract between a page and the
  `Speak` hook in `assets/js/hooks/speak.js`. The hook reads these data
  attributes and nothing else to decide how to pronounce the text, so what is
  and isn't rendered here is what picks a stored clip over synthesis over the
  browser's own voice.
  """
  use ExUnit.Case, async: true

  import HangukoWeb.KoreanComponents
  import Phoenix.LiveViewTest

  @text "안녕하세요"
  @url "/audio/4f/2a/4f2ab1c3.mp3"

  describe "speak_button/1" do
    test "carries the text for the browser to speak" do
      assert [@text] == @text |> button() |> LazyHTML.attribute("data-text")
    end

    test "offers the clip the page already found" do
      assert [@url] == @text |> button(audio: @url) |> LazyHTML.attribute("data-audio")
    end

    test "offers no clip when the page found none" do
      assert [] == @text |> button() |> LazyHTML.attribute("data-audio")
    end

    # "true" rather than a valueless attribute: `dataset.remote` reads one of
    # those as "", which JavaScript treats as false, so the hook would skip
    # straight to browser speech.
    test "asks the server to synthesize when told it may" do
      assert ["true"] == @text |> button(remote: true) |> LazyHTML.attribute("data-remote")
    end

    test "says nothing about the server by default" do
      assert [] == @text |> button() |> LazyHTML.attribute("data-remote")
    end

    test "passes the learner's playback rate through" do
      assert ["0.7"] == @text |> button(rate: 0.7) |> LazyHTML.attribute("data-rate")
    end
  end

  defp button(text, assigns \\ []) do
    assigns = Enum.into(assigns, %{id: "speak", text: text})

    render_component(&speak_button/1, assigns)
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("button")
  end
end
