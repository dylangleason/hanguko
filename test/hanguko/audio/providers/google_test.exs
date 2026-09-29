defmodule Hanguko.Audio.Providers.GoogleTest do
  use ExUnit.Case, async: true

  alias Hanguko.Audio.Providers.Google

  @text "안녕하세요"
  @voice "ko-KR-Chirp3-HD-Achernar"

  # Real MP3 bytes are not valid UTF-8, which is the bug worth guarding
  # against: anything that treats the audio as a string breaks on them.
  @mp3 <<0xFF, 0xFB, 0x90, 0x00, 0x01, 0x02>>

  describe "name/0" do
    test "is the name the clip key is derived from" do
      assert Google.name() == "google"
    end
  end

  describe "synthesize/2" do
    test "posts the text, the voice and MP3 encoding to the v1 endpoint" do
      Req.Test.stub(Google, fn conn ->
        assert conn.method == "POST"
        assert conn.host == "texttospeech.googleapis.com"
        assert conn.request_path == "/v1/text:synthesize"

        assert conn.body_params == %{
                 "input" => %{"text" => @text},
                 "voice" => %{"languageCode" => "ko-KR", "name" => @voice},
                 "audioConfig" => %{"audioEncoding" => "MP3"}
               }

        audio(conn, @mp3)
      end)

      assert {:ok, _} = Google.synthesize(@text, @voice)
    end

    test "authenticates with the configured key in the x-goog-api-key header" do
      Req.Test.stub(Google, fn conn ->
        assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == ["test-api-key"]

        audio(conn, @mp3)
      end)

      assert {:ok, _} = Google.synthesize(@text, @voice)
    end

    test "returns the decoded audio and the content type that was asked for" do
      Req.Test.stub(Google, fn conn -> audio(conn, @mp3) end)

      assert {:ok, %{data: @mp3, content_type: "audio/mpeg"}} = Google.synthesize(@text, @voice)
    end

    test "retries a 429 and returns the audio from the second attempt" do
      Req.Test.expect(Google, fn conn -> Plug.Conn.send_resp(conn, 429, "") end)
      Req.Test.expect(Google, fn conn -> audio(conn, @mp3) end)

      assert {:ok, %{data: @mp3}} = Google.synthesize(@text, @voice)
    end

    test "retries a 503 and returns the audio from the second attempt" do
      Req.Test.expect(Google, fn conn -> Plug.Conn.send_resp(conn, 503, "") end)
      Req.Test.expect(Google, fn conn -> audio(conn, @mp3) end)

      assert {:ok, %{data: @mp3}} = Google.synthesize(@text, @voice)
    end

    test "reports the status when Google refuses the request" do
      Req.Test.stub(Google, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => %{"code" => 400, "message" => "bad voice"}})
      end)

      assert {:error, {:http_error, 400}} = Google.synthesize(@text, @voice)
    end

    test "reports the status when the retries run out" do
      Req.Test.stub(Google, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      assert {:error, {:http_error, 500}} = Google.synthesize(@text, @voice)
    end

    test "reports a request that never got an answer" do
      Req.Test.stub(Google, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, {:transport_error, :econnrefused}} = Google.synthesize(@text, @voice)
    end

    test "reports a 200 with no audioContent" do
      Req.Test.stub(Google, fn conn -> Req.Test.json(conn, %{}) end)

      assert {:error, :invalid_response} = Google.synthesize(@text, @voice)
    end

    test "reports an audioContent that is not base64" do
      Req.Test.stub(Google, fn conn ->
        Req.Test.json(conn, %{"audioContent" => "!not base64!"})
      end)

      assert {:error, :invalid_response} = Google.synthesize(@text, @voice)
    end
  end

  defp audio(conn, data) do
    Req.Test.json(conn, %{"audioContent" => Base.encode64(data)})
  end
end
