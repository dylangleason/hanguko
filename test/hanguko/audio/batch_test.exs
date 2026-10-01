defmodule Hanguko.Audio.BatchTest do
  use Hanguko.DataCase, async: true

  import Hanguko.AudioFixtures

  alias Hanguko.Audio
  alias Hanguko.Audio.Batch
  alias Hanguko.Audio.Clip
  alias Hanguko.Audio.Storage.Local
  alias Hanguko.Fakes.AudioProvider, as: Fake
  alias Hanguko.Fakes.FailingAudioProvider, as: Failing

  # Every text this file can generate a clip for. Paths are derived from the
  # text, so they can be cleaned up without asking the database - `on_exit`
  # runs in ExUnit's own process, which doesn't own the sandbox connection.
  @texts ["어머니", "아버지", "안녕 하세요"]

  setup do
    # Generated clips land in the configured `tmp/audio`, which other test
    # files write to as well, so each test removes the files it created.
    on_exit(fn ->
      for text <- @texts do
        text
        |> Audio.clip_key()
        |> Audio.storage_path("audio/mpeg")
        |> Local.full_path()
        |> File.rm_rf!()
      end
    end)

    :ok
  end

  describe "pending/2" do
    test "returns the texts with no clip yet, and their character count" do
      clip_fixture("어머니")

      result = Batch.pending(["어머니", "아버지", "안녕하세요"])

      assert Enum.sort(result.texts) == ["아버지", "안녕하세요"]
      assert result.characters == 8
    end

    test "counts characters over the canonical text" do
      assert %{characters: 6} = Batch.pending(["  안녕   하세요  "])
    end

    test "is empty when every text already has a clip" do
      clip_fixture("어머니")

      assert %{texts: [], characters: 0} == Batch.pending(["어머니"])
    end

    test "counts a text once when it is given twice" do
      assert %{texts: ["어머니"], characters: 3} == Batch.pending(["어머니", "어머니"])
    end

    # One clip serves both spellings, since the key is derived from the
    # canonical form, so counting them separately would overstate the spend.
    test "counts two spellings of one text once" do
      assert %{texts: ["안녕 하세요"], characters: 6} ==
               Batch.pending(["안녕 하세요", "안녕  하세요"])
    end

    test "reaches the provider not at all" do
      Batch.pending(["어머니"])

      refute_received {Fake, :synthesize, _, _}
    end

    test "is empty when audio is disabled" do
      assert %{texts: [], characters: 0} == Batch.pending(["어머니"], provider: nil)
    end
  end

  describe "generate/2" do
    test "synthesizes and stores a clip for each text" do
      assert %{generated: 2, skipped: 0, failed: []} = Batch.generate(["어머니", "아버지"])

      assert_received {Fake, :synthesize, "어머니", "test-voice"}
      assert_received {Fake, :synthesize, "아버지", "test-voice"}

      for text <- ["어머니", "아버지"] do
        clip = Audio.clip_key(text) |> query_clip()
        refute is_nil(clip)
        assert {:ok, _} = clip.storage_path |> Local.full_path() |> File.read()
      end
    end

    # Without de-duplicating by canonical form these would both be missing, and
    # with `max_concurrency` above one they could be synthesized side by side -
    # paying twice for the clip that the second one then reads back.
    test "buys one clip for two spellings of one text" do
      # `skipped` stays 0: the duplicate is collapsed before the counts are
      # taken, and it never "already had a clip" the way a skip means.
      assert %{generated: 1, skipped: 0, failed: []} =
               Batch.generate(["안녕 하세요", "안녕  하세요"])

      assert_received {Fake, :synthesize, "안녕 하세요", "test-voice"}
      refute_received {Fake, :synthesize, _, _}
    end

    test "records the clips as batch generated, with no requesting user" do
      Batch.generate(["어머니"])

      clip = Audio.clip_key("어머니") |> query_clip()

      assert clip.source == :batch
      assert is_nil(clip.requested_by_id)
    end

    test "skips a text that already has a clip without calling the provider" do
      clip_fixture("어머니")

      assert %{generated: 0, skipped: 1, failed: []} = Batch.generate(["어머니"])

      refute_received {Fake, :synthesize, "어머니", _}
      assert 1 == Repo.aggregate(Clip, :count)
    end

    test "generates nothing the second time round" do
      Batch.generate(["어머니", "아버지"])
      assert %{generated: 0, skipped: 2, failed: []} = Batch.generate(["어머니", "아버지"])

      assert 2 == Repo.aggregate(Clip, :count)
    end

    test "reports the text that failed and keeps going" do
      assert %{generated: 0, skipped: 0, failed: failed} =
               Batch.generate(["어머니"], provider: Failing)

      assert [{"어머니", :synthesis_failed}] == failed
      assert 0 == Repo.aggregate(Clip, :count)
    end

    test "reports invalid text rather than raising" do
      assert %{generated: 1, skipped: 0, failed: [{"hello", :invalid_text}]} =
               Batch.generate(["어머니", "hello"])
    end

    test "is empty for no texts" do
      assert %{generated: 0, skipped: 0, failed: []} == Batch.generate([])
    end
  end

  describe "repair/1" do
    test "re-synthesizes a clip whose audio is gone" do
      clip = clip_fixture("어머니")

      assert %{repaired: 1, failed: []} = Batch.repair()

      assert_received {Fake, :synthesize, "어머니", "test-voice"}
      assert {:ok, _} = clip.storage_path |> Local.full_path() |> File.read()
    end

    test "leaves a clip whose audio is present alone" do
      Batch.generate(["어머니"])

      assert %{repaired: 0, failed: []} = Batch.repair()
    end

    test "reports the clip it could not re-synthesize" do
      clip_fixture("어머니", provider: Failing)

      assert %{repaired: 0, failed: [{"어머니", :synthesis_failed}]} =
               Batch.repair(provider: Failing)
    end

    test "is empty when there are no clips" do
      assert %{repaired: 0, failed: []} == Batch.repair()
    end
  end

  defp query_clip(key), do: Audio.Queries.clips() |> Audio.Queries.with_key(key) |> Repo.one()
end
