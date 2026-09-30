defmodule Mix.Tasks.Hanguko.Audio.GenerateTest do
  # `Mix.shell/1` and the audio config are global, so this file can't run
  # alongside anything else.
  use Hanguko.DataCase, async: false

  import Hanguko.ContentFixtures
  import Hanguko.AudioFixtures

  alias Hanguko.Audio.Clip
  alias Hanguko.Audio.Storage.Local
  alias Hanguko.Fakes.AudioProvider, as: Fake
  alias Mix.Tasks.Hanguko.Audio.Generate

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(shell)

      for %Clip{storage_path: path} <- Repo.all(Clip) do
        path |> Local.full_path() |> File.rm_rf!()
      end
    end)

    deck = deck_fixture()
    item_fixture(deck, korean: "어머니")
    item_fixture(deck, korean: "아버지")

    %{deck: deck}
  end

  describe "run/1 --dry-run" do
    test "reports what it would generate and synthesizes nothing" do
      Generate.run(["--dry-run"])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "2"
      assert message =~ "6"

      refute_received {Fake, :synthesize, _, _}
      assert 0 == Repo.aggregate(Clip, :count)
    end

    test "counts only the texts that have no clip yet" do
      clip_fixture("어머니")

      Generate.run(["--dry-run"])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "1"
    end
  end

  describe "run/1" do
    test "generates a clip for every text the curriculum speaks" do
      Generate.run([])

      assert_received {Fake, :synthesize, "어머니", "test-voice"}
      assert_received {Fake, :synthesize, "아버지", "test-voice"}
      assert 2 == Repo.aggregate(Clip, :count)
    end

    test "reports the plan before the result" do
      Generate.run([])

      assert_received {:mix_shell, :info, [plan]}
      assert_received {:mix_shell, :info, [result]}

      assert plan =~ "2"
      assert result =~ "2"
    end

    test "generates nothing on a second run" do
      Generate.run([])
      Generate.run([])

      assert 2 == Repo.aggregate(Clip, :count)
    end

    test "speaks a jamo item as its example syllable" do
      deck = deck_fixture(kind: :hangeul)
      item_fixture(deck, korean: "ㅐ", kind: :jamo, metadata: %{"example_syllable" => "애"})

      Generate.run([])

      assert_received {Fake, :synthesize, "애", _}
      refute_received {Fake, :synthesize, "ㅐ", _}
    end

    test "raises when audio is disabled" do
      put_audio_env(:provider, nil)

      assert_raise Mix.Error, fn -> Generate.run([]) end
    end

    test "raises after reporting a clip that failed" do
      put_audio_env(:provider, Hanguko.Fakes.FailingAudioProvider)

      assert_raise Mix.Error, fn -> Generate.run([]) end

      assert_received {:mix_shell, :error, [failure]}
      assert failure =~ "어머니"
    end
  end

  describe "run/1 --verify" do
    test "re-synthesizes a clip whose audio has gone missing" do
      clip = clip_fixture("어머니")

      Generate.run(["--verify"])

      assert_received {Fake, :synthesize, "어머니", "test-voice"}
      assert {:ok, _} = clip.storage_path |> Local.full_path() |> File.read()
    end

    test "reports how many it repaired" do
      clip_fixture("어머니")

      Generate.run(["--verify"])

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "1"
    end

    test "leaves a clip whose audio is there alone" do
      Generate.run([])

      # drain the generation, so what's left in the mailbox is verify's doing
      assert_received {Fake, :synthesize, "어머니", _}
      assert_received {Fake, :synthesize, "아버지", _}

      Generate.run(["--verify"])

      refute_received {Fake, :synthesize, _, _}
    end

    test "does not generate anything new" do
      Generate.run(["--verify"])

      assert 0 == Repo.aggregate(Clip, :count)
      refute_received {Fake, :synthesize, _, _}
    end
  end

  test "rejects an unknown switch" do
    assert_raise OptionParser.ParseError, fn -> Generate.run(["--nope"]) end
  end

  defp put_audio_env(key, value) do
    audio = Application.fetch_env!(:hanguko, Hanguko.Audio)
    Application.put_env(:hanguko, Hanguko.Audio, Keyword.put(audio, key, value))
    on_exit(fn -> Application.put_env(:hanguko, Hanguko.Audio, audio) end)
  end
end
