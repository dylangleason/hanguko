defmodule Hanguko.Audio.StorageTest do
  use ExUnit.Case, async: true

  alias Hanguko.Audio.Storage

  setup do
    path = "te/st/#{System.unique_integer([:positive])}.mp3"

    on_exit(fn ->
      path
      |> Storage.Local.full_path()
      |> File.rm_rf!()
    end)

    %{path: path}
  end

  describe "Local.put/3" do
    test "writes data at the specified path without error", %{path: path} do
      expected = "test data"
      assert :ok == Storage.Local.put(path, expected, "audio/mpeg")
      assert expected == File.read!(Storage.Local.full_path(path))
    end

    test "write data to an invalid path results in error", %{path: path} do
      Storage.Local.put(path, "bad data", "audio/mpeg")
      result = Storage.Local.put(Path.join(path, "bad/dir/file.mp3"), "bad data", "audio/mpeg")
      assert {:error, :enotdir} == result
    end

    test "writing same data twice succeeds with same data (idempotent)", %{path: path} do
      expected = "test data"

      assert :ok == Storage.Local.put(path, expected, "audio/mpeg")
      assert expected == File.read!(Storage.Local.full_path(path))

      assert :ok == Storage.Local.put(path, expected, "audio/mpeg")
      assert expected == File.read!(Storage.Local.full_path(path))
    end
  end

  describe "Local.exists?/1" do
    test "is true once the object has been written", %{path: path} do
      refute Storage.Local.exists?(path)

      assert :ok == Storage.Local.put(path, "test data", "audio/mpeg")
      assert Storage.Local.exists?(path)
    end

    test "is false for an object that was removed", %{path: path} do
      assert :ok == Storage.Local.put(path, "test data", "audio/mpeg")
      File.rm!(Storage.Local.full_path(path))

      refute Storage.Local.exists?(path)
    end

    test "is false for a directory at that path", %{path: path} do
      path |> Storage.Local.full_path() |> File.mkdir_p!()

      refute Storage.Local.exists?(path)
    end
  end

  describe "Local.url/1" do
    test "returns the expected URL for a specified path" do
      path = "te/st/example.mp3"
      assert "/audio/#{path}" == Storage.Local.url(path)
    end
  end

  describe "Local.root/0" do
    test "is the configured storage directory" do
      configured =
        :hanguko |> Application.fetch_env!(Hanguko.Audio) |> Keyword.fetch!(:storage_dir)

      assert configured == Storage.Local.root()
    end

    test "is the directory every stored path resolves against" do
      assert Path.join(Storage.Local.root(), "te/st.mp3") == Storage.Local.full_path("te/st.mp3")
    end

    # The Plug.Static in HangukoWeb.Endpoint resolves root/0 on every request
    # under the audio prefix, whether or not audio is switched on, and root/0
    # fetches the key rather than defaulting it. config/runtime.exs sets
    # :storage_dir only inside its GOOGLE_TTS_API_KEY branch, so the base
    # config has to carry a default: without one, a production build with no
    # TTS key raises on any /audio request instead of falling through to 404.
    # Read from the config files because the test environment sets its own.
    test "is configured in production even when no TTS key switches audio on" do
      audio = Config.Reader.read!("config/config.exs", env: :prod)[:hanguko][Hanguko.Audio]

      assert Keyword.has_key?(audio, :storage_dir)
    end
  end
end
