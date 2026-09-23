defmodule Hanguko.AudioTest do
  use Hanguko.DataCase, async: true

  import Hanguko.AudioFixtures

  alias Hanguko.Audio
  alias Hanguko.Audio.Providers.Google
  alias Hanguko.Audio.Storage.Local
  alias Hanguko.Fakes.AudioProvider, as: Fake

  describe "clip_key/2" do
    test "same text gives the same key" do
      assert Audio.clip_key("한") == Audio.clip_key("한")
    end

    test "same composed and decomposed text give the same key" do
      assert Audio.clip_key("한") == Audio.clip_key("\u1112\u1161\u11AB")
    end

    test "surrounding whitespace doesn't change the key" do
      assert Audio.clip_key("한 ") == Audio.clip_key(" 한")
    end

    test "punctuation differences result in different keys" do
      refute Audio.clip_key("가요?") == Audio.clip_key("가요")
    end

    test "different provider options give different keys" do
      refute Audio.clip_key("한", provider: Google) == Audio.clip_key("한", provider: Fake)
    end

    test "different voice options give different keys" do
      refute Audio.clip_key("한") == Audio.clip_key("한", voice: "some-other-voice")
    end

    test "repeated spaces don't change the key" do
      assert Audio.clip_key("안녕 하세요") == Audio.clip_key("안녕  하세요")
    end

    test "spacing changes the key" do
      refute Audio.clip_key("안녕 하세요") == Audio.clip_key("안녕하세요")
    end
  end

  describe "urls_for/2" do
    test "returns the URL of each text that has a clip" do
      clip_1 = clip_fixture("안녕 하세요")
      clip_2 = clip_fixture("안녕 히계세요")

      expected = %{
        "안녕 하세요" => Local.url(clip_1.storage_path),
        "안녕 히계세요" => Local.url(clip_2.storage_path)
      }

      assert expected == Audio.urls_for([clip_1.text, clip_2.text])
    end

    test "leaves out texts that have no clip" do
      no_clip_text = "안녕 하세요"
      clip = clip_fixture("안녕 히계세요")
      expected = %{"안녕 히계세요" => Local.url(clip.storage_path)}

      assert expected == Audio.urls_for([no_clip_text, clip.text])
    end

    test "keys the result by each text as given when several share one clip" do
      clip = clip_fixture("한")
      texts = [clip.text, "한 ", "\u1112\u1161\u11AB"]

      urls = Audio.urls_for(texts)

      assert Map.keys(urls) |> Enum.sort() == Enum.sort(texts)
      assert urls |> Map.values() |> Enum.uniq() |> length() == 1
    end

    test "returns an empty map for missing texts" do
      texts = ["안녕 하세요", "안녕 히계세요"]
      assert %{} == Audio.urls_for(texts)
    end

    test "returns an empty map for no texts" do
      assert %{} == Audio.urls_for([])
    end

    test "combination of shared, existing and non-existing in non-canonical form" do
      clip = clip_fixture("한")
      with_clip = [clip.text, "한 ", "\u1112\u1161\u11AB"]
      without_clip = ["안녕 하세요  ", "안녕 히계세요"]

      urls = Audio.urls_for(without_clip ++ with_clip)

      assert Enum.sort(Map.keys(urls)) == Enum.sort(with_clip)
    end

    test "returns an empty map when audio is disabled" do
      # pass `provider: nil`, with a clip present, so the test stays async
      clip_1 = clip_fixture("안녕 하세요")
      clip_2 = clip_fixture("안녕 히계세요")

      assert %{} == Audio.urls_for([clip_1.text, clip_2.text], provider: nil)
    end
  end
end
