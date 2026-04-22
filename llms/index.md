# ArkeServer — LLM Knowledge Pack

ArkeServer is the **HTTP layer for the Arke ecosystem** — a Phoenix 1.7 application that exposes Arke's dynamic domain model, query DSL, authentication, and file handling as a multi-tenant JSON REST API. Every route translates an HTTP request into calls against `Arke.QueryManager` / `Arke.LinkManager` / `Arke.StructManager` and serializes the result.

This package is the edge. It does no persistence of its own — it depends on `arke` (schema, CRUD pipeline, query), `arke_postgres` (Postgres persistence), and `arke_auth` (Guardian-based JWT + permissions). See the companion packs: [arke](https://github.com/arkemis/arke/llms/index.md) and [arke_postgres](https://github.com/arkemis/arke-postgres/llms/index.md).

**Current version:** 0.5.0 · **License:** Apache-2.0 · **Source:** <https://github.com/arkemis/arke-server> · **Hex:** <https://hex.pm/packages/arke_server>

## Read order

Start with `overview.md`. After that the files are independent — jump to whichever matches the task.

| File | When to read |
|---|---|
| [overview.md](overview.md) | **Always read first.** Mental model: route namespaces, plug pipelines, project/permission/unit resolution, response envelope. |
| [reference.md](reference.md) | Looking up a specific controller action, plug, or utility module. |
| [recipes.md](recipes.md) | Common tasks: mounting the router, adding a custom controller, configuring OAuth, writing a mailer adapter. |
| [gotchas.md](gotchas.md) | Something behaves unexpectedly. Sharp edges around the `arke-project-key` header, auth fallbacks, `String.to_existing_atom`, and the filter DSL. |
| [design.md](design.md) | Questions about *why* something is shaped this way — useful when debugging or evaluating roadmap changes. |

## What ArkeServer is

- The REST edge over Arke — every read/write/topology operation a client performs lands here and is forwarded to `Arke.*`.
- A multi-tenant router: every request carries an `arke-project-key` header that scopes all downstream queries.
- A pluggable auth surface: Guardian-based JWT (via `arke_auth`) plus a pluggable OAuth strategy system (Google, Apple, Facebook, Microsoft built-in).
- An OpenAPI 3 provider: every controller ships with a paired `*ControllerSpec` module; the spec is served at `/lib/doc/openapi` with SwaggerUI at `/lib/doc/swaggerui`.
- A bulk-import endpoint for xlsx uploads (via `Arke.System.import/1`).

## What ArkeServer is not

- Not an HTTP framework — it sits on top of Phoenix. Mount `ArkeServer.Router` into your own Phoenix app or run `ArkeServer.Endpoint` directly.
- Not a persistence layer. It requires `arke_postgres` (or an alternative backend configured on `arke`).
- Not the authentication core. It composes `arke_auth`'s Guardian modules into plug pipelines.
- Not a Phoenix LiveView host. The endpoint is JSON-first; the browser pipeline exists only for SSO redirects (currently commented out).

## Minimum you need to use it

```elixir
# mix.exs
{:arke,          "~> 0.6.0"},
{:arke_postgres, "~> 0.5.0"},
{:arke_auth,     "~> 0.4.4"},
{:arke_server,   "~> 0.5.0"}

# config/config.exs — wire the persistence seam (required by arke)
config :arke,
  persistence: %{
    arke_postgres: %{
      create:         &ArkePostgres.create/2,
      update:         &ArkePostgres.update/2,
      delete:         &ArkePostgres.delete/2,
      execute_query:  &ArkePostgres.Query.execute/2,
      create_project: &ArkePostgres.create_project/1,
      delete_project: &ArkePostgres.delete_project/1
    }
  }

config :arke_auth, ArkeAuth.Guardian,
  issuer: "arke_auth",
  secret_key: System.get_env("GUARDIAN_SECRET"),
  token_ttl: %{"access" => {7, :days}, "refresh" => {30, :days}}

config :arke_server, ArkeServer.Endpoint,
  url: [host: "localhost"],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [accepts: ~w(json)]

# Optional: mailer for auth emails (signup/reset/otp). Required for OTP flows.
config :arke_server, :mailer_module, MyApp.Mailer
```

Without `:persistence` configured in `arke`, the first request crashes inside `Arke.QueryManager`. Without `:mailer_module`, OTP-mode signin/signup returns the code generation result but sends nothing.

## What the API surface looks like

All routes live under `/lib`. A minimal tour:

- `POST /lib/auth/signin` — credentials → `{access_token, refresh_token, member}`.
- `POST /lib/:arke_id/unit` — create a Unit of any Arke, body is the Unit's data.
- `GET  /lib/:arke_id/unit` — paginated list with `filter=`, `order[]=`, `offset=`, `limit=`, `load_links=`, `load_values=`, `load_files=`.
- `GET  /lib/:arke_id/unit/:unit_id/link/:direction` — walk the link graph.
- `GET  /lib/:arke_id/function/:function_name` — invoke an Arke-level function (dispatches to the module's `call_func`).
- `POST /lib/arke_project/unit` — create a new project (tenant). Scoped to `:arke_system`.

See [reference.md](reference.md#routes-at-a-glance) for the full route table.
