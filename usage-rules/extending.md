# Extending

- Never edit `ArkeServer.Router` — mount it and add your own controllers in
  the host app's router, replicating the `:project`/`:auth_api` pipelines for
  your routes.
- The assigns contract set by the built-in plugs: `:arke_project` (project id
  atom, from `GetProject`), `:filter` (parsed `?filter=`, from
  `BuildFilters`), `:permission_filter` (from `Permission`), `:unit` (from
  `GetUnit`).
- In custom controllers: `use ArkeServer, :controller`; reply ONLY through
  `ArkeServer.ResponseManager.send_resp/2,5` (it keeps the response
  envelope); reuse `ArkeServer.Utils.{QueryFilters, QueryOrder}` for
  filter/order parsing:

  ```elixir
  defmodule MyApp.ImportController do
    use ArkeServer, :controller
    alias ArkeServer.ResponseManager

    def import(conn, %{"arke_id" => arke_id}) do
      project = conn.assigns[:arke_project]
      arke =
        Arke.Boundary.ArkeManager.get(arke_id, project)
        |> Arke.Core.Unit.update(runtime_data: %{conn: conn}, metadata: %{project: project})

      case apply(arke.__module__, :import, [arke]) do
        {:ok, summary, status} -> ResponseManager.send_resp(conn, status, %{content: summary})
        {:error, errors}       -> ResponseManager.send_resp(conn, 400, nil, errors)
      end
    end
  end
  ```

- Mailer: `use ArkeServer.Mailer`, override `signin/3`, `signup/3`,
  `reset_password/3`, send with `send_email/1` (`:to` required; `:from` falls
  back to the configured `default_sender`, else raises):

  ```elixir
  config :arke_server, :mailer_module, MyApp.Mailer
  config :arke_server, MyApp.Mailer,
    adapter: ArkeServer.Swoosh.Adapters.Mailtrap,
    api_key: System.get_env("MAILTRAP_API_KEY"),
    default_sender: {"MyApp", "noreply@myapp.com"}
  config :swoosh, :api_client, Swoosh.ApiClient.Req
  ```

  The `:swoosh` line must live in the host app — library config does not
  propagate, and req is the only API client ArkeServer ships.

- Custom OAuth provider: `use ArkeServer.OAuth.Core`; implement
  `handle_request/1`, `info/1`, `uid/1`, `handle_cleanup/1`; register it under
  `config :arke_server, ArkeServer.Plugs.OAuth, providers: [...]`; and seed an
  `oauth_<name>` Arke into the `:oauth_provider` group of `:arke_system`. The
  plug only honors `base_url` from config/env — the default is
  `lib/auth/signin`.
- Route order matters: routes inherit every `pipe_through` declared above
  them in the scope — a route added at the bottom of a scope gets the whole
  pipeline staircase.
- For custom `ArkeError` handling, note the status mapping is closed
  (`:unauthorized` 401, `:forbidden` 403, `:not_found` 404, everything else
  400).
