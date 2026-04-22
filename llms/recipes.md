# Recipes — Common Tasks

Task-oriented snippets. Each recipe is self-contained; read [overview.md](overview.md) first for the mental model.

All recipes assume:
- `:arke`, `:arke_postgres`, `:arke_auth`, `:arke_server` listed in `mix.exs`.
- `config :arke, persistence: %{...}` configured (see [index.md](index.md#minimum-you-need-to-use-it)).
- `config :arke_auth, ArkeAuth.Guardian, ...` configured with issuer + secret.
- A seeded project (e.g. `mix arke.seed_project --project my_project`).

---

## Run the server in dev

```bash
iex -S mix phx.server
# -> listens on http://localhost:4000 by default
```

Every request must carry the `arke-project-key` header (except health, openapi, and some auth endpoints). Without it → 401.

```bash
curl http://localhost:4000/lib/person/unit \
  -H "arke-project-key: my_project" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

---

## Sign in and get a token

```bash
curl -X POST http://localhost:4000/lib/auth/signin \
  -H "Content-Type: application/json" \
  -H "arke-project-key: my_project" \
  -d '{"username": "ada@example.com", "password": "secret"}'

# → 200
# {
#   "content": {
#     "id": "member-uuid", "arke_id": "member", "data": {...},
#     "access_token": "ey…", "refresh_token": "ey…"
#   },
#   "messages": []
# }
```

Use `access_token` as `Authorization: Bearer <token>` on subsequent requests. Refresh with `POST /lib/auth/refresh`.

---

## Create, read, update, delete a Unit

```bash
# CREATE
curl -X POST http://localhost:4000/lib/person/unit \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Ada", "email": "ada@example.com", "age": 36}'

# READ one
curl http://localhost:4000/lib/person/unit/ada \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN"

# LIST with filters, order, pagination, link expansion
curl 'http://localhost:4000/lib/person/unit?filter=gte(age,18)&order[]=inserted_at;desc&limit=20&load_links=true' \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN"

# UPDATE
curl -X PUT http://localhost:4000/lib/person/unit/ada \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"age": 37}'

# DELETE
curl -X DELETE http://localhost:4000/lib/person/unit/ada \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN"
```

---

## Compose filters

```
filter=and(gte(age,23),contains(name,string))
filter=or(eq(role,admin),and(gt(age,30),isnull(deleted_at)))
filter=not(in(status,draft,archived))
filter=eq(customer.name,Ada)            # nested — walks :customer link parameter
```

Parser errors → 400 with a messages payload. `isnull(param_id)` checks for null; every other operator takes `(param_id,value)`. `in` accepts a parenthesized list: `in(role,(admin,editor,viewer))`.

---

## Order and paginate

```
?order[]=inserted_at;desc&order[]=name;asc
?offset=40&limit=20
?count_only=true          # skip the fetch; returns just the count as a number
```

Direction is `asc` or `desc` — parsed with `String.to_existing_atom/1`, so those are the only valid values.

---

## Walk the link graph

```bash
# Everything linked as children of ada, up to depth 3, type "friendship"
curl 'http://localhost:4000/lib/person/unit/ada/link/child?depth=3&link_type=friendship' \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN"

# Count only
curl 'http://localhost:4000/lib/person/unit/ada/link/child/count?link_type=friendship' \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN"
```

Direction is `child` or `parent` (atoms, parsed with `String.to_existing_atom`).

---

## Create / delete a link

```bash
# Link two Units together
curl -X POST http://localhost:4000/lib/person/unit/ada/link/friendship/person/unit/grace \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"metadata": {"since": "2024-01-01"}}'

# Update link metadata
curl -X PUT .../link/friendship/person/unit/grace \
  -d '{"metadata": {"weight": 0.8}}'

# Delete
curl -X DELETE .../link/friendship/person/unit/grace \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN"
```

Directly manipulates `arke_link` Units. For most cases, prefer setting `:link` parameter values on the parent Unit via `PUT /lib/:arke_id/unit/:unit_id`.

---

## Attach a parameter to an Arke at runtime

```bash
# Add parameter "nickname" to "person" Arke
curl -X POST http://localhost:4000/lib/person/parameter/nickname \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"metadata": {"required": false, "default_string": ""}}'

# Update the parameter-on-arke link's metadata
curl -X PUT .../parameter/nickname -d '{"metadata": {"required": true}}'
```

Creates an `arke_link` of type `"parameter"` from the Arke Unit to the Parameter Unit. Both must already exist.

---

## Call an Arke or Unit function

The `call_arke_function` / `call_unit_function` routes dispatch to `ArkeManager.call_func(arke, function_atom, args)`, which calls the module bound to the Arke (via `__module__`):

```elixir
defmodule MyApp.Invoice do
  use Arke.System

  arke id: :invoice do
    parameter :total, :float
  end

  # Arke-level function: args = [arke]
  def generate_report(arke) do
    {:ok, %{generated_at: DateTime.utc_now()}, 200}
  end

  # Unit-level function: args = [arke, unit]
  def send_reminder(arke, unit) do
    # ...
    {:ok, "sent", 200}
  end

  # File download
  def export_pdf(_arke, unit) do
    {:file, pdf_binary, "invoice-#{unit.id}.pdf"}
  end
end
```

```bash
curl http://localhost:4000/lib/invoice/function/generate_report \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN"

curl http://localhost:4000/lib/invoice/unit/inv-001/function/export_pdf \
  -H "arke-project-key: my_project" -H "Authorization: Bearer $TOKEN" \
  -o invoice.pdf
```

Return-value shapes are mapped in `ArkeController#call_arke_function`:
- `{:file, binary, filename}` → `send_download`
- `{:error, msg, status}` / `{:error, msg}` → error response
- `{:ok, content, status[, messages]}` → JSON response with `content:`
- anything else → 200 with `%{content: result}`

---

## Bulk import from xlsx

The `Arke.System.import/1` hook is exposed via the function endpoint pattern. A typical route:

```elixir
# In your host app, not in arke_server directly — add to your own router
post "/lib/:arke_id/import", MyApp.ImportController, :import
```

```elixir
defmodule MyApp.ImportController do
  use ArkeServer, :controller

  def import(conn, %{"arke_id" => arke_id}) do
    project = conn.assigns[:arke_project]
    arke =
      Arke.Boundary.ArkeManager.get(arke_id, project)
      |> Arke.Core.Unit.update(runtime_data: %{conn: conn}, metadata: %{project: project})

    case apply(arke.__module__, :import, [arke]) do
      {:ok, summary, status} ->
        ArkeServer.ResponseManager.send_resp(conn, status, %{content: summary})
      {:error, errors} ->
        ArkeServer.ResponseManager.send_resp(conn, 400, nil, errors)
    end
  end
end
```

The xlsx file must be uploaded as `multipart/form-data` with the file field expected by `Arke.System.import`. See `arke/llms/recipes.md#bulk-import-from-xlsx`.

---

## Mount the router in a parent app

If you're embedding ArkeServer in your own Phoenix app:

```elixir
# mix.exs
defp deps do
  [
    {:arke_server, "~> 0.5.0"},
    # ...
  ]
end

# lib/my_app/endpoint.ex — instead of running ArkeServer.Endpoint directly
defmodule MyApp.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app
  # ... your parsers, plugs ...
  plug MyApp.Router
end

# lib/my_app/router.ex — forward to ArkeServer.Router
defmodule MyApp.Router do
  use Phoenix.Router

  scope "/" do
    forward "/", ArkeServer.Router
  end
end
```

Configure `:arke_server, ArkeServer.Endpoint` *and* `:my_app, MyApp.Endpoint` — the ArkeServer endpoint config is still consulted for CORS / parsers when routes resolve inside it.

For OpenAPI, set `config :arke_server, :endpoint_module, MyApp.Endpoint` so the spec's `servers` list reflects your host app's URL.

---

## Configure OAuth providers

```elixir
# config/runtime.exs
config :arke_server, ArkeServer.Plugs.OAuth,
  base_url: "lib/auth/signin",
  providers: [
    google:    {ArkeServer.OAuth.Provider.Google,    []},
    apple:     {ArkeServer.OAuth.Provider.Apple,     []},
    facebook:  {ArkeServer.OAuth.Provider.Facebook,  []},
    microsoft: {ArkeServer.OAuth.Provider.Microsoft, []}
  ]
```

Set provider-specific env vars:

```bash
export GOOGLE_CLIENT_ID="..."
export APPLE_CLIENT_ID="com.example.app"
export APPLE_TEAM_ID="..."
export APPLE_PRIVATE_KEY_ID="..."
export APPLE_PRIVATE_KEY="/path/to/AuthKey.p8"      # or the PEM content
export FACEBOOK_CLIENT_ID="..."
export FACEBOOK_CLIENT_SECRET="..."
```

Frontend flow (client-side):
1. User authenticates with the provider SDK, gets `id_token`.
2. Frontend `POST /lib/auth/signin/:provider` with `{account: {id_token}}` (Google) or `{token, nonce}` (Apple) or `{id_token, access_token}` (Microsoft) in the body/query.
3. `OAuthController#handle_client_login` verifies the token, finds or creates the OAuth unit + linked user, and returns `access_token` + `refresh_token`.

---

## Add a custom OAuth provider

```elixir
defmodule MyApp.OAuth.Provider.GitHub do
  use ArkeServer.OAuth.Core
  @private_oauth_key :arke_server_oauth

  def handle_request(%Plug.Conn{body_params: %{"token" => token}} = conn) do
    case HTTPoison.get("https://api.github.com/user", [{"Authorization", "Bearer #{token}"}]) do
      {:ok, %{status_code: 200, body: body}} ->
        put_private(conn, @private_oauth_key, Jason.decode!(body))
      _ ->
        Plug.Conn.assign(conn, :arke_server_oauth_failure, Error.create(:auth, "invalid token"))
    end
  end

  def info(conn) do
    data = conn.private[@private_oauth_key]
    %UserInfo{email: data["email"], first_name: data["name"]}
  end

  def uid(conn), do: to_string(conn.private[@private_oauth_key]["id"])

  def handle_cleanup(conn), do: put_private(conn, @private_oauth_key, nil)
end
```

Then register it:

```elixir
config :arke_server, ArkeServer.Plugs.OAuth,
  providers: [github: {MyApp.OAuth.Provider.GitHub, []}]
```

And seed an `oauth_github` Arke into `:arke_system` so the OAuthController's `check_provider` recognizes it. See `arke_auth` for the `oauth_provider` group membership convention.

---

## Write a mailer

```elixir
defmodule MyApp.Mailer do
  use ArkeServer.Mailer

  def signup(_conn, _params, opts) do
    member = Keyword.get(opts, :member)
    code   = Keyword.get(opts, :code)
    mode   = Keyword.get(opts, :mode)

    case mode do
      "otp" ->
        send_email(
          to: member.data.email,
          subject: "Your OTP code",
          html: "<p>Your signup code is <b>#{code}</b>.</p>"
        )

      _ ->
        send_email(
          to: member.data.email,
          subject: "Welcome",
          html: "<p>Welcome to MyApp, #{member.data.first_name}!</p>"
        )
    end
  end

  def signin(_conn, _member, _opts), do: :ok
  def reset_password(_conn, member, opts), do: ...
end

# config/config.exs
config :arke_server, :mailer_module, MyApp.Mailer

config :arke_server, MyApp.Mailer,
  adapter: ArkeServer.Swoosh.Adapters.Mailtrap,
  api_key: System.get_env("MAILTRAP_API_KEY"),
  default_sender: {"MyApp", "noreply@myapp.com"}
```

`default_sender` is required unless every `send_email` call supplies `from:`. Available adapters include the bundled `Mailtrap` and `OneSignal` plus anything from Swoosh.

---

## Write a permission filter

Permissions live in `arke_auth` but ArkeServer consumes them. The `filter` string in a permission record is any filter-DSL expression, with `{{arke_member}}` substituted for the requesting member's ID:

```
eq(owner,{{arke_member}})
or(eq(owner,{{arke_member}}),eq(is_public,true))
```

The `Permission` plug parses this via `QueryFilters.get_from_string/2` and intersects it with every query.

`child_only: true` on a permission means "restrict to units in the member's link subtree" — `QueryFilters.apply_member_child_only/3` applies `QueryManager.link(query, member, depth: 10)`.

---

## Create a new project (tenant)

```bash
# You need a super_admin token for this
curl -X POST http://localhost:4000/lib/arke_project/unit \
  -H "Authorization: Bearer $SUPERADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id": "acme", "label": "ACME Corp"}'
```

This calls `QueryManager.create(:arke_system, arke_project, ...)`, which triggers `Arke.Core.Project.on_create/2` → `persistence[:arke_postgres][:create_project]`, provisioning the Postgres schema. Then seed it:

```bash
mix arke.seed_project --project acme
```

Clients that need the new project use `arke-project-key: acme`.

---

## Impersonation

For admin-tools that act on behalf of another member, send *two* bearer tokens:

```
Authorization:      Bearer <admin_access_token>
impersonate-token:  Bearer <target_member_access_token>
```

The `Permission` plug uses `ImpersonateAuthPipeline`, which loads both resources; `ArkeAuth.Guardian.get_member(conn, impersonate: true)` returns the impersonated one. Permission filters and the `child_only` restriction apply to the impersonated member, so your admin sees what that user would see.

---

## Debug a request

```elixir
# In iex:
iex> Phoenix.Router.routes(ArkeServer.Router) |> Enum.filter(&(&1.verb == :get))
iex> Arke.Boundary.ArkeManager.get(:person, :my_project)        # verify the Arke exists
iex> Arke.Boundary.ArkeManager.get_parameters(some_arke)         # inspect its fields
iex> Arke.Boundary.ParameterManager.get(:email, :my_project)     # verify a filter parameter
iex> ArkeAuth.Utils.Permission.get_public_permission(:person, :my_project)   # check public access
```

Enable verbose Phoenix logging if routes aren't matching:

```elixir
config :logger, level: :debug
```

And check `conn.assigns` for `:arke_project`, `:filter`, `:permission_filter`, `:unit` — if any are missing, the plug for that value didn't run (wrong pipeline, path param typo, project header missing).

---

## Export the DB structure (super_admin)

```bash
curl http://localhost:4000/lib/arke_dev_function/export_arke_db_stucture?project=my_project \
  -H "Authorization: Bearer $SUPERADMIN_TOKEN"
```

Delegates to `Arke.Utils.Export.get_db_structure/2`. Useful for generating registry JSON fixtures. Member must have `arke_id: :super_admin`.

---

## Enable health probes (Kubernetes)

The routes already exist:

```
GET /lib/health/ready   →  readiness
GET /lib/health/live    →  liveness
GET /lib/health/start   →  startup
```

All three return 200 unconditionally. If you need real checks (DB connectivity, Arke manager alive, …), wrap them in a custom controller and forward to these as a fallback.
