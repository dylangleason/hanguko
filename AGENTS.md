This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- Build queries in the context's `Queries` module (`Hanguko.Content.Queries`, `Hanguko.SRS.Queries`, `Hanguko.Progress.Queries`), never in the context itself. Query modules return `Ecto.Query` structs and never call `Repo`; contexts run them and own every transaction and lock. Name bindings with `as:` and have narrowing functions (`query -> query`) match on the binding name, not position. Contexts don't `import Ecto.Query`. `Hanguko.Accounts` is generated code and is exempt. See "Queries" in `guides/architecture.md`
- Always pass the assign `current_scope` to context modules as first argument. When performing queries, use `current_scope.user` to filter the query results
- Web-layer conventions (Phoenix 1.8, HEEx, LiveView, forms, routing and authentication, JS/CSS) live in `lib/hanguko_web/AGENTS.md`; LiveView test conventions live in `test/hanguko_web/AGENTS.md`. Both load when working under those directories

### Documentation guidelines

Documentation is part of the change, not a follow-up. When you introduce a
feature, a subsystem, a data model or a domain abstraction, **update the
documentation in the same commit as the code**. Which document depends on
what changed:

- **`README.md`** — a new Mix task, a new step to get the app running, or any
  change to the commands used day to day (its table is the list of those
  commands). Also update it when a workflow changes, such as how the
  curriculum is edited
- **`guides/architecture.md`** — the *shape* of the system: its C4 context,
  container and component views, the curriculum/progress split, and the rules
  that cut across contexts (scoping, study days, queries). Update it for a new
  context or an external dependency, or when one of those cross-cutting rules
  changes. Say **why** it is shaped that way, not just what it does — the
  rationale is the part that can't be read off the code.
  **Feature mechanics do not go here.** If a rule can name one module, it
  belongs in that module's `@moduledoc`; the guide links to it. The test: a
  new contributor should be able to read this guide in a couple of minutes
- **`guides/domain-model.md`** — a new table, a new column that carries
  meaning, a new relationship, or a new invariant. Keep the Mermaid ER
  diagram and the "rules worth keeping in mind" list in step with the schema
- **`guides/deployment.md`** — anything about how a build reaches production:
  the Dockerfile, the CI and release workflows, what `bin/migrate` does,
  runtime configuration, the pinned Elixir/OTP versions
- **`@moduledoc`** — every new module says what it is responsible for and how
  it relates to its neighbors. New public functions get a `@doc`. Invariants
  that a reader would otherwise have to infer (why a card has no `new` state,
  why content is retired rather than deleted) belong next to the code that
  enforces them
- **`AGENTS.md`** — a convention future work has to follow

Rules for writing it:

- **Verify every claim against the code before writing it down.** Read the
  module, run the function, check the migration. Documentation that is
  confidently wrong is worse than none
- Prefer explaining decisions and invariants over restating structure a
  reader can see. Never paste a file listing that will drift
- **Never state a rule in two places.** A guide that repeats a moduledoc is
  one copy that will go stale; link to the moduledoc instead. The rule lives
  next to the code that enforces it
- Mermaid diagrams use `flowchart` and `erDiagram`, never the experimental
  `C4Context` / `C4Container` types, so they render the same on GitHub and in
  `mix docs`. `mix.exs` loads Mermaid into the generated HTML through
  `before_closing_body_tag/1`, pinned to an exact version with an SRI hash —
  move `@mermaid_version` and `@mermaid_integrity` together, and open a guide
  in `doc/` afterwards, because a stale hash blocks the script silently and
  the diagrams fall back to code blocks
- Keep prose in `guides/`. `doc/` is git-ignored because `mix docs` (ExDoc)
  generates into it, so anything written there is lost
- Add new guides to the `extras` list in `mix.exs` so `mix docs` picks them up
- `mix docs` must build without warnings; an undefined `t()` or a broken
  reference means a type or a link is missing

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behavior by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->

<!-- usage-rules-end -->