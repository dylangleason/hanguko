defmodule Hanguko.Audio.Providers.Google do
  @moduledoc """
  Synthesizes Korean speech with the Google Cloud Text-to-Speech API.

  One `POST` to `texttospeech.googleapis.com/v1/text:synthesize` per clip,
  authenticated with an API key in the `x-goog-api-key` header. The response
  is JSON with the audio in a base64 `audioContent` field, so the bytes are
  decoded here and the content type is the one we asked for - the response
  carries no content type of its own, since the caller chooses the encoding.

  MP3 is requested because every browser plays it and the clips are speech at
  a small bitrate, where the format barely matters. The voice is named by the
  caller (`Hanguko.Audio` passes the configured one) and must be a `ko-KR`
  voice: the language code is fixed here, as the app has nothing to say in any
  other language.

  Configured under its own key, separate from `Hanguko.Audio`, because the API
  key belongs to this adapter and nothing else should be able to reach it:

      config :hanguko, Hanguko.Audio.Providers.Google, api_key: "..."

  The key is read with `Keyword.fetch!/2`, so a Google provider with no key
  raises rather than failing per request: `config/runtime.exs` only selects
  this provider when a key is present, and audio is disabled otherwise. The
  key is never logged. It travels in a request header, which Req does not
  redact the way it redacts `authorization`, so **nothing here may log the
  request or its headers** - only the response status and body, which Google
  does not echo the key into.

  Requests retry on the transient statuses (408, 429, 5xx) and on transport
  errors. Req's default `:safe_transient` would not: it skips POSTs, on the
  assumption that a repeated POST creates a second thing. Synthesis creates
  nothing, so `retry: :transient` is both safe and necessary here.
  """

  @behaviour Hanguko.Audio.Provider

  @endpoint "https://texttospeech.googleapis.com/v1/text:synthesize"
  @language_code "ko-KR"
  @audio_encoding "MP3"
  @content_type "audio/mpeg"

  @impl true
  def name, do: "google"

  @doc """
  Synthesizes `text` in `voice`, returning
  `{:ok, %{data: mp3_bytes, content_type: "#{@content_type}"}}`.

  `POST #{@endpoint}` with the API's three-part body, sent as JSON:

      %{
        input: %{text: text},
        voice: %{languageCode: "#{@language_code}", name: voice},
        audioConfig: %{audioEncoding: "#{@audio_encoding}"}
      }

  Errors are values, never raises, because `Hanguko.Audio.speak/4` turns every
  one of them into a fallback to browser speech:

    * `{:error, {:http_error, status}}` - Google answered and refused, or kept
      failing until the retries ran out. A 400 usually means the voice name or
      the language code is wrong; a 403 means the key is rejected
    * `{:error, {:transport_error, reason}}` - the request never got an answer
    * `{:error, :invalid_response}` - a 200 whose body has no `audioContent`,
      or one that isn't valid base64. Not expected, but a missing clip is
      better than writing an empty object to storage

  Nothing is retried past the failure: `Hanguko.Audio` inserts no row when
  synthesis fails, so the next request for the same text tries again.

  Options for the request itself come from the `:req_options` key of this
  module's config and are merged last, which is how the tests point it at a
  `Req.Test` stub instead of the network.
  """
  @impl true
  def synthesize(text, voice) do
    options = req_options()

    result =
      Req.post(
        @endpoint,
        Keyword.merge(
          [
            retry: :transient,
            headers: %{"x-goog-api-key" => api_key!()},
            json: %{
              input: %{text: text},
              voice: %{languageCode: @language_code, name: voice},
              audioConfig: %{audioEncoding: @audio_encoding}
            }
          ],
          options
        )
      )

    case result do
      # Req.TransportError and Req.HTTPError both mean nothing answered: a
      # refused connection, or a stream the server dropped unprocessed.
      {:error, %{reason: reason}} ->
        {:error, {:transport_error, reason}}

      {:ok, %{status: status}} when status != 200 ->
        {:error, {:http_error, status}}

      {:ok, %{status: 200, body: %{"audioContent" => encoded}}} when is_binary(encoded) ->
        decode_data(encoded)

      _ ->
        {:error, :invalid_response}
    end
  end

  defp decode_data(encoded) do
    case Base.decode64(encoded) do
      {:ok, decoded} -> {:ok, %{data: decoded, content_type: @content_type}}
      :error -> {:error, :invalid_response}
    end
  end

  defp api_key!(), do: :hanguko |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(:api_key)

  defp req_options,
    do: Application.get_env(:hanguko, __MODULE__, []) |> Keyword.get(:req_options, [])
end
