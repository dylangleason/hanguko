# Deployment

How a commit becomes something running in production, and why each step is
shaped the way it is. The commands themselves — building the image locally,
running it, the environment variables it needs — are in the
[README](../README.md#ci-and-releases).

## The artifact is an image, not a tarball

A production build is a **Docker image around a Mix release**, built from the
`Dockerfile` that `mix phx.gen.release --docker` generated. It's an image
rather than a release tarball because the image carries the runtime the
release was compiled against: glibc, OpenSSL and the locales. A tarball only
runs on a host that matches the machine that built it, which makes "it works
on my laptop" a deployment strategy rather than a joke.

The build is two stages. `hexpm/elixir:<elixir>-erlang-<otp>-debian-<debian>`
compiles the release with `MIX_ENV=prod`, including `mix assets.deploy`, and
the plain `debian` image of the same version runs it. Nothing from the build
stage survives except the release directory, so Mix, Hex and the sources are
not in the running container.

## Two workflows

* **CI** (`.github/workflows/ci.yml`) runs on pull requests and on pushes to
  `main`. It runs the `mix precommit` checks against Postgres 18 and builds
  the docs with `--warnings-as-errors`, which is what enforces the
  documentation rule in `AGENTS.md` — a broken reference fails the build. It
  also builds the image without pushing it, so a change that breaks the
  Dockerfile fails in the pull request that caused it rather than at release
  time.
* **Release** (`.github/workflows/release.yml`) runs on `v*` tags. Its first
  job refuses a tag that doesn't match `version` in `mix.exs`, so the Git tag,
  the image tag and the app's own version can't disagree. It then calls CI as
  a reusable workflow on the tagged commit — the same checks, not a second
  copy of them, and `skip_image: true` because this workflow builds the image
  itself. Only if that passes does it push to GitHub Container Registry and
  create a GitHub Release.

The ordering is the point: a tag is a claim that a specific commit is
releasable, so the release workflow re-verifies that commit instead of
trusting that CI passed on `main` at some point.

## The curriculum is imported at deploy time

Content lives in the database, loaded from the packs — but a release has no
Mix, so it can't run `mix hanguko.content.import`.
`Hanguko.Release.import_content/0` runs the same importer over the packs
bundled into the release, and `rel/overlays/bin/migrate` calls it right after
`Hanguko.Release.migrate/0`:

```sh
./hanguko eval "Hanguko.Release.migrate(); Hanguko.Release.import_content()"
```

That order matters, because a pack can use a column a migration adds. The
importer is idempotent and all-or-nothing (see `Hanguko.Content.Importer`), so
running it on every deploy is safe, and a release carrying an invalid pack
fails at `bin/migrate` — before the new version starts serving — rather than
half-importing and leaving the curriculum in a state nobody wrote.

Run `bin/migrate` from the new image against the database before starting the
new version.

## Version pinning

The Elixir and OTP versions are pinned in three places: the development
machine (see the README), the `ELIXIR_VERSION` / `OTP_VERSION` env in
`ci.yml`, and the `ARG`s at the top of the `Dockerfile`. They have to move
together, or CI would test on a different runtime than production runs. The
Dockerfile carries a comment saying so; there is no check that enforces it.

## Configuration

Production configuration is read at boot from the environment in
`config/runtime.exs`, not baked into the image, so the same image runs in any
environment. `DATABASE_URL`, `SECRET_KEY_BASE` and `PHX_HOST` are required;
`PORT`, `POOL_SIZE`, `ECTO_IPV6` and `DNS_CLUSTER_QUERY` are optional. Mail
delivery for magic-link sign-in is configured there too, on `Hanguko.Mailer`.
