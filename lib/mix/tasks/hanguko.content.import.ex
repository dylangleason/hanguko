defmodule Mix.Tasks.Hanguko.Content.Import do
  @shortdoc "Imports curated content packs into the database"

  @moduledoc """
  Imports the YAML content packs in `priv/content` (see
  `Hanguko.Content.Importer` for the format).

      $ mix hanguko.content.import
      $ mix hanguko.content.import --path path/to/packs

  The import is validated as a whole before anything is written, and is safe
  to run repeatedly.
  """
  use Mix.Task

  alias Hanguko.Content.Importer

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [path: :string])
    Logger.configure(level: :info)

    case Importer.import_dir(opts[:path] || Importer.default_path()) do
      {:ok, stats} ->
        Mix.shell().info("Imported content from #{opts[:path] || "priv/content"}")
        Mix.shell().info(format_stats("decks", stats.decks))
        Mix.shell().info(format_stats("items", stats.items))
        Mix.shell().info(format_stats("grammar", stats.grammar_points))

      {:error, errors} ->
        Enum.each(errors, &Mix.shell().error("  " <> &1))
        Mix.raise("Content import failed with #{length(errors)} error(s); nothing was written")
    end
  end

  defp format_stats(label, stats) do
    "  #{label}: #{stats.created} created, #{stats.updated} updated, " <>
      "#{stats.unchanged} unchanged, #{stats.retired} retired"
  end
end
