# Hanguko

A Phoenix LiveView app for learning Korean: Hangeul, vocabulary, everyday
phrases and grammar, studied with spaced repetition (FSRS).

The curriculum lives in the repo as YAML content packs under `priv/content`
and is loaded into the database by an importer, so lessons are reviewed the
same way as code. Everything a learner does — enrolments, cards, review
history — is per user and separate from that content.

## Requirements

* Elixir 1.18 or newer (developed on 1.20 / OTP 29)
* PostgreSQL 18 (a `docker-compose.yml` is included; podman works too)
* Node is *not* required — assets are built with esbuild and Tailwind
  binaries fetched by Mix

## Getting started

```sh
podman-compose up -d          # or: docker compose up -d
mix setup                     # deps, database, seed content, assets
mix phx.server                # http://localhost:4000
```

`mix setup` runs `ecto.create`, `ecto.migrate` and `priv/repo/seeds.exs`,
which imports the content packs.

Sign-in is by magic link. In development the mail is not sent anywhere: open
[`/dev/mailbox`](http://localhost:4000/dev/mailbox) and follow the link.

## Common tasks

| Command | What it does |
| --- | --- |
| `mix setup` | Install dependencies, set up the database, build assets |
| `mix phx.server` | Run the app on port 4000 (`PORT=4001 mix phx.server` to move it) |
| `iex -S mix phx.server` | The same, with a shell attached |
| `mix precommit` | Compile with warnings as errors, drop unused deps, format, test — run this before committing |
| `mix test` | Run the test suite (creates and migrates the test database first) |
| `mix test path/to/test.exs:42` | Run one test or file |
| `mix hanguko.content.import` | Load `priv/content` into the database; safe to re-run |
| `mix hanguko.content.import --path tmp/packs` | Import from somewhere else |
| `mix ecto.migrate` / `mix ecto.rollback` | Apply or undo migrations |
| `mix ecto.gen.migration name` | Start a new migration |
| `mix ecto.reset` | Drop, recreate, migrate and re-seed — **deletes all study progress** |
| `mix docs` | Build the HTML documentation into `doc/` (git-ignored) |
| `mix assets.build` | Rebuild CSS and JS once |
| `mix assets.deploy` | Minified assets plus a digest, for releases |

Restart the server after adding a dependency; the running app won't pick it
up on its own.

## Editing the curriculum

Content packs are YAML files under `priv/content/{hangeul,vocab,phrases,grammar}`.
Edit a pack, then:

```sh
mix hanguko.content.import
```

The importer validates every pack before writing anything, reports errors
with the file and item they came from, and is idempotent: re-running it with
no edits changes no rows. Content that disappears from the packs is marked
retired rather than deleted, so review history survives an edit. The format
is documented in `Hanguko.Content.Importer` and in
[guides/architecture.md](guides/architecture.md#content-packs).

## Tests

```sh
mix test                                   # everything
mix test test/hanguko/srs                  # the scheduler and queue
mix test test/hanguko/content/packs_test.exs   # sanity checks on the real content
```

Scheduling is deterministic in tests: interval fuzz is off, and every
function that depends on the time takes `now` as an argument.

## CI and releases

Two GitHub Actions workflows live in `.github/workflows`:

* **CI** (`ci.yml`) runs on every pull request and every push to `main`. It
  does what `mix precommit` does (unused deps, formatting, warnings as errors,
  tests against Postgres 18), builds the docs with warnings as errors, and
  builds the production Docker image without publishing it. CI uses Elixir
  1.20.2 / OTP 29; change `ELIXIR_VERSION` and `OTP_VERSION` there and the
  versions in the `Dockerfile` together.
* **Release** (`release.yml`) runs when a version tag is pushed. The tag must
  match `version` in `mix.exs`:

  ```sh
  # bump version in mix.exs to 0.2.0, merge it, then:
  git tag v0.2.0
  git push origin v0.2.0
  ```

  It runs CI, pushes the image to GitHub Container Registry as
  `ghcr.io/dylangleason/hanguko:0.2.0` (also tagged `0.2` and with the commit
  SHA), and creates a GitHub Release with generated notes. A tag with a
  suffix, such as `v0.2.0-rc.1`, is marked as a pre-release.
* **Claude Issue Bot** (`claude-issue-bot.yml`) runs when an issue is labeled
  `claude-bot`. Claude implements the issue on a new branch and opens a pull
  request against `main` that closes the issue. It never compiles, formats,
  or tests the change itself, and never merges on its own — `ci.yml` and a
  human reviewer are what actually verify the PR.

To build and run the image locally:

```sh
podman build -t hanguko .      # or: docker build
podman run --rm -p 4000:4000 \
  -e DATABASE_URL=ecto://postgres:postgres@host.containers.internal/hanguko_dev \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST=localhost \
  hanguko
```

The image runs `bin/server`. Before starting a new version against a
database, run `bin/migrate` from the same image. It applies migrations, then
imports the content packs bundled in the release, because Mix isn't available
in production to run `mix hanguko.content.import`:

```sh
podman run --rm -e DATABASE_URL=... -e SECRET_KEY_BASE=... -e PHX_HOST=... hanguko /app/bin/migrate
```

The production environment variables are listed in `config/runtime.exs`:
`DATABASE_URL`, `SECRET_KEY_BASE` and `PHX_HOST` are required; `PORT`,
`POOL_SIZE`, `ECTO_IPV6` and `DNS_CLUSTER_QUERY` are optional.

## Where things live

```
lib/hanguko/          contexts: Accounts, Content, SRS, plus the Korean language helpers
lib/hanguko_web/      LiveViews, components and the router
priv/content/         the curriculum, as YAML packs
priv/repo/migrations/ schema history
assets/js/hooks/      speech synthesis and study keyboard shortcuts
guides/               architecture and domain model
test/                 mirrors lib/
```

## Documentation

Read the guides straight from the repository:

* [guides/architecture.md](guides/architecture.md) — how the pieces fit: contexts,
  the content pipeline, the study loop, and why it's shaped this way
* [guides/domain-model.md](guides/domain-model.md) — the tables, what they mean and
  the rules they enforce
* `AGENTS.md` — Phoenix 1.8 and LiveView conventions this codebase follows

Or build them together with the module documentation, where the guides and
every `@doc` are cross-linked:

```sh
mix docs
open doc/index.html      # Linux: xdg-open doc/index.html
```

ExDoc writes into `doc/`, which is git-ignored — that's why the guides
themselves live in `guides/`. The modules are grouped there by what they do:
Curriculum, Spaced repetition, Korean, Accounts and Web.
