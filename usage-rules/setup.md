# Setup

- Adding `arke_server` as a dependency starts `ArkeServer.Endpoint` in your
  supervision tree automatically. If you mount `ArkeServer.Router` inside your
  own endpoint, disable the built-in listener or you get a second server /
  boot failure:

  ```elixir
  config :arke_server, ArkeServer.Endpoint, server: false,
    secret_key_base: System.get_env("SECRET_KEY_BASE")
  ```

- Minimum required config — the first request crashes without it:

  ```elixir
  config :arke, persistence: %{
    arke_postgres: %{
      create: &ArkePostgres.create/2, update: &ArkePostgres.update/2,
      update_key: &ArkePostgres.update_key/2, delete: &ArkePostgres.delete/2,
      execute_query: &ArkePostgres.Query.execute/2,
      create_project: &ArkePostgres.create_project/1,
      delete_project: &ArkePostgres.delete_project/1,
      repo: ArkePostgres.Repo, init: &ArkePostgres.init/0
    }
  }

  config :arke_auth, ArkeAuth.Guardian,
    issuer: "my_app", secret_key: System.get_env("GUARDIAN_SECRET"),
    token_ttl: %{"access" => {7, :days}, "refresh" => {30, :days}}

  config :arke_server, ArkeServer.Endpoint,
    url: [host: "localhost"], secret_key_base: System.get_env("SECRET_KEY_BASE"),
    http: [port: 4000], render_errors: [accepts: ~w(json)], server: true

  config :arke_server, ecto_repos: [ArkePostgres.Repo]
  config :phoenix, :json_library, Jason
  ```

- `config :arke_server, :endpoint_module, MyApp.Endpoint` sets the OpenAPI
  `servers:` list (defaults to `http://localhost:4000`).
- The shipped `config/dev.exs` is essentially empty — `config/test.exs` is the
  only complete configuration template; copy from there.
- Run standalone with `iex -S mix phx.server`; introspect all routes with
  `mix phx.routes ArkeServer.Router`.
- Mount inside a host Phoenix app with
  `forward "/", ArkeServer.Router` in your router.
- CORS is wide open at the library endpoint (`origins: "*"`); front it with
  your own gate if you need stricter CORS.
