# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Curated study content lives in priv/content and is loaded by the same
# importer as `mix hanguko.content.import`, so this is safe to re-run.

Mix.Task.run("hanguko.content.import")
