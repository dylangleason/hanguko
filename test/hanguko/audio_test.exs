defmodule Hanguko.AudioTest do
  use ExUnit.Case, async: true

  alias Hanguko.Audio
  alias Hanguko.Audio.Providers.Google
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
end
