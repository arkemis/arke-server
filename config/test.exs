import Config

config :arke,
  persistence: %{
    arke_postgres: %{
      create: &ArkePostgres.create/2,
      update: &ArkePostgres.update/2,
      update_key: &ArkePostgres.update_key/2,
      delete: &ArkePostgres.delete/2,
      execute_query: &ArkePostgres.Query.execute/2,
      create_project: &ArkeServer.Support.ProjectSchemaStub.create_project/1,
      delete_project: &ArkeServer.Support.ProjectSchemaStub.delete_project/1,
      repo: ArkePostgres.Repo,
      init: &ArkePostgres.init/0
    }
  }

config :arke_auth, ArkeAuth.Guardian,
  issuer: "arke_auth",
  secret_key: "5hyuhkszkm8jilkDxrXGTBz1z1KJk5dtVwLgLOXHQRsPEtxii3wFcAbx4Gtj1aQB",
  verify_issuer: true,
  token_ttl: %{"access" => {7, :days}, "refresh" => {30, :days}}

config :arke_server, ArkeServer.Endpoint,
  render_errors: [formats: [json: ArkeServer.ErrorJSON], layout: false]

config :arke_server, mailer_module: ArkeServer.TestMailer

config :arke_server, ArkeServer.TestMailer, adapter: Swoosh.Adapters.Test

config :arke_server, ecto_repos: [ArkePostgres.Repo]

config :arke_postgres, ArkePostgres.Repo,
  username: "postgres",
  password: "postgres",
  database: System.get_env("DB_NAME") || "myapp_test",
  hostname: System.get_env("DB_HOSTNAME") || "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
