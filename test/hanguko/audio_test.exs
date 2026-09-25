defmodule Hanguko.AudioTest do
  use Hanguko.DataCase, async: true

  import Hanguko.AccountsFixtures
  import Hanguko.AudioFixtures

  alias Hanguko.Audio
  alias Hanguko.Audio.Clip
  alias Hanguko.Audio.Providers.Google
  alias Hanguko.Audio.Storage.Local
  alias Hanguko.Audio.Queries
  alias Hanguko.Fakes.AudioProvider, as: Fake
  alias Hanguko.Fakes.FailingAudioProvider, as: Failing
  alias Hanguko.Fakes.RacingAudioProvider, as: Racing

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

  describe "ensure_clip/2" do
    test "returns the stored clip without calling the provider" do
      text = "어머니"
      clip1 = clip_fixture(text)

      {result, clip2} = Audio.ensure_clip(text)

      refute_received {Fake, :synthesize, _, _}

      assert :ok == result
      assert clip1.id == clip2.id
    end

    test "synthesizes, stores and inserts a clip on a miss" do
      {result, clip} = Audio.ensure_clip("안녕히계세요")
      assert :ok == result

      remove_on_exit(clip)

      assert_received {Fake, :synthesize, "안녕히계세요", "test-voice"}

      refute is_nil(clip.id)
      refute clip.key |> query_clip() |> is_nil()
    end

    test "writes the synthesized bytes at the clip's storage path" do
      {clip_result, clip} = Audio.ensure_clip("안녕히계세요")
      assert :ok == clip_result

      remove_on_exit(clip)

      {file_result, data} = Local.full_path(clip.storage_path) |> File.read()

      assert :ok == file_result
      assert String.contains?(clip.storage_path, clip.key)
      assert clip.byte_size == byte_size(data)
    end

    test "stores the canonical text and its character count" do
      text = "안녕하세요"
      {clip_result, clip} = Audio.ensure_clip(text)
      assert :ok == clip_result

      remove_on_exit(clip)

      canonical_text = Audio.canonical(text)
      assert canonical_text == clip.text
      assert String.length(canonical_text) == clip.characters
    end

    test "records the source and the requesting user" do
      user = user_fixture()
      {clip_result, clip} = Audio.ensure_clip("감사합니다", requested_by_id: user.id)
      assert :ok == clip_result

      remove_on_exit(clip)

      assert user.id == clip.requested_by_id
      assert :on_demand == clip.source
    end

    test "defaults to an on-demand clip with no requesting user" do
      {clip_result, clip} = Audio.ensure_clip("감사합니다")
      assert :ok == clip_result

      remove_on_exit(clip)

      assert :on_demand == clip.source
    end

    test "returns one clip for texts that differ only in spacing" do
      {clip1_result, clip1} = Audio.ensure_clip("안녕히 계세요")
      assert :ok == clip1_result

      {clip2_result, clip2} = Audio.ensure_clip("안녕히  계세요")
      assert :ok == clip2_result

      remove_on_exit(clip1)

      assert clip1.key == clip2.key
      assert clip1.text == clip2.text
      refute clip1.key |> query_clip() |> is_nil()
    end

    # Whether the two processes actually collide is up to the scheduler, but
    # either way one clip exists and both callers hold it.
    test "returns the same clip when two processes miss at once" do
      tasks = for _ <- 1..2, do: Task.async(fn -> Audio.ensure_clip("한") end)
      [{:ok, a}, {:ok, b}] = Task.await_many(tasks)

      assert a.id == b.id
      assert 1 == Repo.aggregate(Clip, :count)
    end

    test "returns the clip another process inserted while it was synthesizing" do
      assert {:ok, clip} = Audio.ensure_clip("한", provider: Racing)
      remove_on_exit(clip)

      refute is_nil(clip.id)

      # the racer's row, not the one we built
      assert :batch == clip.source
      assert 0 == clip.byte_size
      assert 1 == Repo.aggregate(Clip, :count)
    end

    test "returns :disabled when no provider is configured" do
      assert {:error, :disabled} == Audio.ensure_clip("한", provider: nil)
    end

    test "returns :invalid_text for text without Hangul" do
      assert {:error, :invalid_text} == Audio.ensure_clip("hello")
    end

    test "returns :invalid_text for text with characters other than Hangul, spaces, numbers and punctuation" do
      assert {:error, :invalid_text} == Audio.ensure_clip(" hello, 안녕 hello")
    end

    test "returns :invalid_text for text longer than 200 characters" do
      assert {:error, :invalid_text} == Audio.ensure_clip(String.duplicate("한글", 101))
    end

    test "accepts Hangul with spaces and punctuation" do
      {result, clip} = Audio.ensure_clip("안녀히 계세요!")
      assert :ok == result
      remove_on_exit(clip)
    end

    test "inserts nothing when the provider fails" do
      text = "안녀히 계세요!"
      {result, _} = Audio.ensure_clip("안녀히 계세요!", provider: Failing)
      assert :error = result
      assert Audio.clip_key(text) |> query_clip() |> is_nil()
    end
  end

  defp query_clip(key), do: Queries.clips() |> Queries.with_key(key) |> Repo.one()

  # `ensure_clip/2` writes into the configured `tmp/audio`, which other test
  # files write to as well, so tests remove the file they created rather than
  # the directory.
  defp remove_on_exit(%Clip{storage_path: path} = clip) do
    on_exit(fn -> path |> Local.full_path() |> File.rm_rf!() end)
    clip
  end
end
