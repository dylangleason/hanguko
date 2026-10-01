defmodule HangukoWeb.AudioHook do
  @moduledoc """
  Answers the `"audio:speak"` event, which the `Speak` hook in
  `assets/js/hooks/speak.js` pushes for a button with no pre-generated clip: a
  syllable from the builder, a stem from the grammar "try it" box, or content
  imported since the last `mix hanguko.audio.generate`.

  Attached with `Phoenix.LiveView.attach_hook/4` through the router's
  `on_mount` lists, rather than written as a `handle_event/3` clause in each
  LiveView. Every page that shows Korean has a speak button, and a page that
  forgot the clause would crash the first time one was pressed. It must be
  listed after the `HangukoWeb.UserAuth` hook, which is what assigns
  `current_scope`.

  Replies take one of two shapes:

      %{url: "/audio/4f/2a/4f2ab1....mp3"}
      %{error: "rate_limited"}

  The error is one of `"unauthenticated"`, `"disabled"`, `"rate_limited"`,
  `"budget_exceeded"` and `"invalid_text"`, with `"unavailable"` for everything
  else. They are strings rather than the reasons `Hanguko.Audio.speak/4`
  actually returns because one of those can be any term - a provider's status
  tuple, say - and a term JSON can't encode would take the LiveView down rather
  than fall back to browser speech. `"unavailable"` is also logged, because
  from the outside a dead API key looks exactly like working browser speech.

  A non-binary or missing `text` is refused as `"invalid_text"` here, before
  `Hanguko.Audio.speak/4` is called at all - that function expects a binary.
  An oversized `text` is also refused as `"invalid_text"`, but by `speak/4`
  itself, which checks the byte size before canonicalizing, hashing or summing
  the month's characters, so an oversized payload buys none of that work.

  Also assigns `speak_remote?`, via `Hanguko.Audio.available?/2`, which is
  what a page passes to `HangukoWeb.KoreanComponents.speak_button/1` as
  `remote`. There is no sense offering a round trip that would be refused for
  want of a signed-in user or a configured provider. Deciding it here rather
  than per page keeps one copy of the rule, and a page that gets it wrong
  either wastes a request per button or quietly drops every learner to browser
  speech.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Hanguko.Audio

  require Logger

  # Client errors
  @reported ~w(unauthenticated disabled rate_limited budget_exceeded invalid_text)a

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:speak_remote?, offer_synthesis?(socket.assigns.current_scope))
      |> attach_hook(:audio_speak, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  defp handle_event("audio:speak", %{"text" => text}, socket) when is_binary(text) do
    reply =
      case Audio.speak(socket.assigns.current_scope, text, DateTime.utc_now()) do
        {:ok, url} -> %{url: url}
        {:error, reason} -> %{error: reason(reason)}
      end

    {:halt, reply, socket}
  end

  defp handle_event("audio:speak", _params, socket) do
    {:halt, %{error: "invalid_text"}, socket}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp offer_synthesis?(scope), do: Audio.available?(scope)

  defp reason(reason) when reason in @reported, do: Atom.to_string(reason)

  defp reason(other) do
    Logger.warning("audio:speak failed: #{inspect(other)}")
    "unavailable"
  end
end
