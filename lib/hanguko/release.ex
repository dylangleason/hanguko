defmodule Hanguko.Release do
  @moduledoc """
  Database tasks for production, where the release runs without Mix.

  The release's `bin/migrate` script runs `migrate/0` and then
  `import_content/0`. A deploy therefore applies new migrations and brings
  the curriculum in line with the content packs bundled in that release,
  which is what `mix ecto.migrate` and `mix hanguko.content.import` do in
  development.
  """
  alias Hanguko.Audio
  alias Hanguko.Audio.Batch
  alias Hanguko.Content
  alias Hanguko.Content.Importer

  @app :hanguko

  @doc "Runs every pending migration for each of the app's repos."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc "Rolls `repo` back to the migration `version`."
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Imports the content packs bundled in the release (`priv/content`).

  Like `mix hanguko.content.import`, it validates every pack before writing
  anything, and it is safe to run on every deploy. It raises when a pack is
  invalid, so a deploy with broken content stops here instead of starting.
  """
  def import_content do
    load_app()
    {:ok, _} = Application.ensure_all_started(:yaml_elixir)

    {:ok, stats, _} =
      Ecto.Migrator.with_repo(Hanguko.Repo, fn _repo ->
        case Importer.import_dir(Importer.default_path()) do
          {:ok, stats} ->
            stats

          {:error, errors} ->
            raise "content import failed with #{length(errors)} error(s); nothing was written:\n" <>
                    Enum.join(errors, "\n")
        end
      end)

    IO.puts("Imported content packs")

    for {label, key} <- [decks: :decks, items: :items, grammar: :grammar_points] do
      %{created: created, updated: updated, unchanged: unchanged, retired: retired} = stats[key]

      IO.puts(
        "  #{label}: #{created} created, #{updated} updated, " <>
          "#{unchanged} unchanged, #{retired} retired"
      )
    end

    :ok
  end

  @doc """
  Pre-renders audio for the curriculum, as `mix hanguko.audio.generate` does in
  development.

  Meant for `bin/hanguko eval \'Hanguko.Release.generate_audio()\'` after a
  deploy that adds content, not for every boot: it calls a metered API, and a
  release that synthesized on startup would do so again on every restart.

  Unlike `import_content/0`, this reports failures and returns `:ok` rather than
  raising. Broken content is a reason to stop a deploy; a clip that didn't
  render is not, because every page falls back to the browser's own speech.
  """
  def generate_audio do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Hanguko.Repo, fn _repo ->
        if Audio.enabled?() do
          texts = Content.speech_texts()
          %{texts: missing, characters: characters} = Batch.pending(texts)

          IO.puts("Generating #{length(missing)} clips (#{characters} characters)")

          %{generated: generated, skipped: skipped, failed: failed} = Batch.generate(texts)

          IO.puts("  #{generated} generated, #{skipped} already stored")

          for {text, reason} <- failed do
            IO.puts("  failed: #{text} (#{inspect(reason)})")
          end
        else
          IO.puts("No audio provider is configured; nothing to generate")
        end
      end)

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
