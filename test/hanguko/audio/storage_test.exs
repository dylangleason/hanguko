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

  describe "Local.url/1" do
    test "returns the expected URL for a specified path" do
      path = "te/st/example.mp3"
      assert "/audio/#{path}" == Storage.Local.url(path)
    end
  end
end
