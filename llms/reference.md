# Reference — Public Surface

Module-by-module reference. Signatures reflect arke_server 0.5.0 source. Only public entry points that callers (including sibling packages and host apps) use are listed; internal helpers are omitted.

## Module map

| Module | Role |
|---|---|
| `ArkeServer` | `use` macro: injects `Phoenix.Controller` / `Phoenix.Router` + `Plug.Exception` for `Arke.Errors.ArkeError` |
| `ArkeServer.Application` | OTP callback — starts `Telemetry` and `Endpoint` |
| `ArkeServer.Endpoint` | `Phoenix.Endpoint` — static, parsers, CORS, session |
| `ArkeServer.Router` | Pipelines + route table |
| `ArkeServer.Routes` | Moduledoc-rendered route dump (for tooling) |
| `ArkeServer.ResponseManager` | Standardized JSON response envelope |
| `ArkeServer.Telemetry` | `:telemetry_poller` supervisor |
| `ArkeServer.*Controller` | One per resource; always paired with `ArkeServer.Openapi.*ControllerSpec` |
| `ArkeServer.Plugs.*` | Auth / project / unit / permission / filters / oauth pipelines |
| `ArkeServer.Utils.*` | Filter parser, order parser, query processor, OneSignal client, Apple secret |
| `ArkeServer.Mailer` | `__using__` macro for a host-app Swoosh mailer with `signin/3`, `signup/3`, `reset_password/3` defoverridable hooks |
| `ArkeServer.Swoosh.Adapters.Mailtrap` | Swoosh adapter for Mailtrap API |
| `ArkeServer.Swoosh.Adapters.OneSignal` | Swoosh adapter for OneSignal email-as-notification |
| `ArkeServer.OAuth.Core` | `__using__` macro for OAuth provider strategies |
| `ArkeServer.OAuth.Provider.{Google,Apple,Facebook,Microsoft}` | Built-in provider strategies |
| `ArkeServer.ApiSpec` | `OpenApiSpex.OpenApi` callback + shared parameter definitions |
| `ArkeServer.Openapi.Spec` | Per-controller `__using__` macro wiring `open_api_operation/1` |
| `ArkeServer.ErrorHandlers.{Auth,SSOAuth}` | Guardian error → 401 JSON |

---

## Routes at a glance

| Method | Path | Controller#action | Pipelines |
|---|---|---|---|
| GET | `/lib/health/{ready,live,start}` | `HealthController` | — |
| GET / POST | `/lib/doc/{swaggerui,openapi}` | OpenApiSpex plugs | `:openapi` |
| GET / POST | `/lib/auth/signin` | `AuthController#signin` | `:project` |
| POST | `/lib/auth/:arke_id/signup` | `AuthController#signup` | `:project` |
| POST | `/lib/auth/recover_password` | `AuthController#recover_password` | `:project` |
| POST | `/lib/auth/reset_password[/:token]` | `AuthController#reset_password` | `:project` |
| POST | `/lib/auth/refresh` | `AuthController#refresh` | `:project` |
| POST | `/lib/auth/verify` | `AuthController#verify` | `:auth_api` |
| POST | `/lib/auth/change_password` | `AuthController#change_password` | `:auth_api` |
| POST | `/lib/auth/signin/:provider` | `OAuthController#handle_client_login` | `:oauth` |
| POST | `/lib/auth/:member/:provider` | `OAuthController#handle_create_member` | `:sso_auth_api` |
| GET / POST / PUT / DELETE | `/lib/arke_project/unit[/:unit_id]` | `ProjectController` | `:auth_api` |
| GET | `/lib/arke_dev_function/export_arke_db_stucture` | `ArkeDevFunctionController` | `:tmp_auth_pipe` (super_admin only) |
| GET | `/lib/group/:group_id/{arke,struct,unit[/:unit_id]}` | `GroupController` | `:project`, `:auth_api` |
| GET / POST | `/lib/group/:group_id/function/:function_name` | `GroupController#call_group_function` | `:project`, `:auth_api` |
| GET | `/lib/:arke_id/{struct,group,count}` | `ArkeController` / `StructController` | `:project`, `:auth_api`, `:get_unit` |
| POST | `/lib/:arke_id/unit` | `ArkeController#create` | ... |
| GET | `/lib/:arke_id/unit[/:unit_id]` | `ArkeController#get_all_unit` / `#get_unit` | ... |
| PUT | `/lib/:arke_id/unit/:unit_id` | `UnitController#update` | ... |
| DELETE | `/lib/:arke_id/unit/:unit_id` | `ArkeController#delete` | ... |
| GET | `/lib/:arke_id/unit/:arke_unit_id/link/:direction[/count]` | `TopologyController#get_node[_count]` | ... |
| GET | `/lib/:arke_id/unit/:arke_unit_id/struct` | `StructController#get_unit_struct` | ... |
| POST / PUT / DELETE | `/lib/:arke_id/unit/:arke_unit_id/link/:link_id/:arke_id_two/unit/:unit_id_two` | `TopologyController#{create,update,delete}_node` | ... |
| POST / PUT | `/lib/:arke_id/parameter/:arke_parameter_id` | `TopologyController#{add,update}_parameter` | ... |
| GET / POST / PUT / DELETE | `/lib/parameter/:parameter_id[/:unit_id]` | `ParameterController` | ... |
| GET / POST | `/lib/:arke_id/function/:function_name` | `ArkeController#call_arke_function` | ... |
| GET / POST | `/lib/:arke_id/unit/:unit_id/function/:function_name` | `ArkeController#call_unit_function` | ... |
| GET | `/lib/unit` | `UnitController#search` | ... |

To introspect at runtime: `mix phx.routes ArkeServer.Router` or read the `ArkeServer.Routes` moduledoc.

---

## `ArkeServer` (the use macro)

```elixir
use ArkeServer, :controller    # injects Phoenix.Controller + Plug.Conn import
use ArkeServer, :router        # injects Phoenix.Router + Plug.Conn + Phoenix.Controller imports
use ArkeServer, :channel       # Phoenix.Channel (unused by the library itself)
```

Plus a `Plug.Exception` implementation for `Arke.Errors.ArkeError`: `:unauthorized → 401`, `:forbidden → 403`, `:not_found → 404`, anything else → `400`.

---

## `ArkeServer.Endpoint`

Standard `Phoenix.Endpoint` for `:arke_server`:

- Session via cookie (`_arke_server_key`, signing salt baked in — override via config if needed).
- `Plug.Static` for `assets/fonts/images/favicon.ico/robots.txt`.
- `Plug.Parsers` for `urlencoded` / `multipart` (max 40 MB) / `json`.
- `Corsica`, origin `"*"`, `allow_headers: :all` (adjust for production).
- Mounts `ArkeServer.Router`.

Code reloading is enabled only when `code_reloading?` is true (dev).

## `ArkeServer.Router`

Pipelines:

- `:api` → `NotAuthPipeline` (for endpoints that must be called *without* a token).
- `:auth_api` → `Permission` (public-first, then member auth).
- `:tmp_auth_pipe` → `AuthPipeline` (bare auth, no permission check — used only by `arke_dev_function`).
- `:project` → `GetProject` + `BuildFilters`.
- `:get_unit` → `GetUnit`.
- `:oauth` → `OAuth` (provider dispatcher).
- `:sso_auth_api` → `SSOAuthPipeline`.
- `:openapi` → `OpenApiSpex.Plug.PutApiSpec, module: ArkeServer.ApiSpec`.
- `:browser` → session + CSRF + fetch_flash (currently only used by commented-out OAuth redirect routes).

## `ArkeServer.ResponseManager`

```elixir
send_resp(conn, status)                                                 # 204, empty body
send_resp(conn, status, data, message \\ [], encode \\ :json)
```

Envelope shapes:
- `%{items: [...]}` → `{content: {items:, count: length(items)}, messages:}`
- `%{items: [...], count: N}` → `{content: {items:, count:}, messages:}`
- `%{content: c}` → `{content: c, messages:}`
- Other / nil / `""` → `{content: ..., messages:}`

`message` accepts a list, map, or string — strings become `[%{context: nil, message: s}]`.

---

## Controllers

### `ArkeController` (Arke-level resource)

```elixir
get_unit(conn, %{"unit_id" => _})                  # GET  /lib/:arke_id/unit/:unit_id
create(conn, %{"arke_id" => id})                   # POST /lib/:arke_id/unit
delete(conn, %{"unit_id" => _, "arke_id" => _})    # DELETE /lib/:arke_id/unit/:unit_id
get_all_unit(conn, %{"arke_id" => id})             # GET  /lib/:arke_id/unit
get_all_unit_count(conn, %{"arke_id" => id})       # GET  /lib/:arke_id/count
call_arke_function(conn, %{"arke_id" =>, "function_name" =>})
call_unit_function(conn, %{"arke_id" =>, "unit_id" =>, "function_name" =>})
get_groups(conn, %{"arke_id" => id})               # GET  /lib/:arke_id/group
```

`get_all_unit` supports a **coordinates filter**: supplying `?latitude=&longitude=[&radius=30]` adds `latitude__gte/lte` and `longitude__gte/lte` bounds (great-circle rectangle approximation). Expects `:latitude` and `:longitude` parameters on the target Arke.

`call_arke_function` / `call_unit_function` dispatch to `ArkeManager.call_func(arke, function_atom, args)`. The function's return shape determines the response:
- `{:file, binary, filename}` → `send_download/3`
- `{:error, msg, status}` / `{:error, msg}` → error response (status or 404)
- `{:ok, content, status[, messages]}` → success
- anything else → 200 with `%{content: result}`

### `UnitController`

```elixir
search(conn, _)        # GET /lib/unit — global search across all Arkes in project
update(conn, %{"unit_id" =>, "arke_id" =>})   # PUT /lib/:arke_id/unit/:unit_id
```

`search` defaults to `limit=100`.

### `TopologyController`

```elixir
get_node(conn, %{"arke_id" =>, "arke_unit_id" =>, "direction" =>})   # GET /link/:direction
get_node_count(...)                                                    # GET /link/:direction/count
create_node(conn, %{...})                                              # POST link
update_node(conn, %{...})                                              # PUT  link (requires "metadata" in body)
delete_node(conn, %{...})                                              # DELETE link
add_parameter(conn, %{"arke_parameter_id" =>, "arke_id" =>})           # POST parameter link (type "parameter")
update_parameter(conn, %{...})                                         # PUT  parameter link metadata
```

Direction is parsed with `String.to_existing_atom/1` — only `:child` or `:parent` are valid (see [gotchas.md](gotchas.md#the-direction-atom-trap)).

### `ParameterController`

```elixir
get_parameter_value(conn, %{"parameter" => id})     # stub — returns {count:0, items:[]}
update_parameter_value(conn, _)                     # stub — 200
add_link_parameter_value(conn, _)                   # stub — 201
remove_link_parameter_value(conn, _)                # stub — 204
```

**These are mostly stubs.** The endpoints exist in the router but the bodies are placeholder. Don't rely on them unless implementing.

### `GroupController`

```elixir
call_group_function(conn, %{"group_id" =>, "function_name" =>})
struct(conn, %{"group_id" => id})       # Union of group's Arke parameters as a synthetic struct
get_arke(conn, %{"group_id" => id})     # List the Arkes in this group
get_unit(conn, %{"group_id" => id})     # List Units whose arke_id is in the group
unit_detail(conn, %{"group_id" =>, "unit_id" =>})
```

### `StructController`

```elixir
get_unit_struct(conn, %{"arke_id" =>, "arke_unit_id" =>})   # Struct shape for a specific Unit
get_arke_struct(conn, %{"arke_id" => id})                    # Struct shape for the Arke definition
```

Delegates to `Arke.StructManager.get_struct/2` / `/3`.

### `AuthController`

```elixir
signup(conn, %{"arke_id" => arke_id})         # body: data for the member's arke + arke_system_user
signin(conn, params)                          # three arities: {token}, {auth_token}, {username, password}
refresh(conn, %{"refresh_token" => t})
verify(conn, _)
change_password(conn, %{"old_password" =>, "password" =>})
recover_password(conn, %{"email" => e})
reset_password(conn, params)                  # default-mode: {new_password, token}; otp_mail: {new_password, otp, email}

mailer_module()                               # reads Application.get_env(:arke_server, :mailer_module)
update_member_access_time(member, args \\ [])
```

Auth mode is chosen by `AUTH_MODE` env var — `"default"` (password) or `"otp_mail"` (username+password → OTP email/SMS → OTP code). A super_admin member always uses default mode regardless of `AUTH_MODE`.

Review-mode env vars: `APP_REVIEW_EMAIL` (comma-separated) and `APP_REVIEW_CODE` (default `"1234"`) short-circuit the OTP flow for listed email addresses — intended for App Store review testers.

### `OAuthController`

```elixir
handle_client_login(conn, _)        # POST /lib/auth/signin/:provider — token from client SDK
handle_create_member(conn, params)  # POST /lib/auth/:member/:provider — complete SSO signup
request(conn, _)                    # 404 fallback
callback(conn, _)                   # legacy redirect callback (paths currently commented out)
```

### `ProjectController`

```elixir
create(conn, params)
update(conn, %{"unit_id" => id})
delete(conn, %{"unit_id" => id})
get_all_unit(conn, _)
get_unit(conn, %{"unit_id" => id})
```

All scoped to `:arke_system`. Creating invokes `Arke.Core.Project.on_create/2`, which hits `persistence[:arke_postgres][:create_project]` to provision the DB schema.

### `HealthController`

`ready/2`, `live/2`, `start/2` — all 200, no body. Kubernetes probes.

### `ArkeDevFunctionController`

```elixir
export_arke_db_stucture(conn, params)   # super_admin only; delegates to Arke.Utils.Export
```

---

## Plugs

### `ArkeServer.Plugs.GetProject`

Reads the `arke-project-key` header, looks up the matching `arke_project` Unit in `:arke_system`, and assigns the project's `id` (atom) to `:arke_project`. On failure → 401 halt.

### `ArkeServer.Plugs.GetUnit`

Reads `:unit_id` or `:arke_unit_id` path params, resolves the Unit with permission + member-child filters applied, and assigns `conn.assigns[:unit]`. Also supports a special "`arke_id::unit_id`" syntax in path segments for multi-unit operations. On nil → 404 halt.

### `ArkeServer.Plugs.Permission`

See [overview.md#the-permission-plug](overview.md#the-permission-plug). Key entry points in the source:

- `call/2` dispatches on path params (`arke_id` / `group_id` / `parameter_id`) or regex-extracts from the request path.
- `check_permission/2` runs the public-first-then-member dance.
- `{{arke_member}}` in a permission filter template is replaced with the current member's ID.

### `ArkeServer.Plugs.BuildFilters`

Parses `conn.query_params["filter"]` (on GET) into `conn.assigns[:filter]` as `{logic_atom, negate_bool, base_filter_list}`. On parse failure → 400 halt.

### `ArkeServer.Plugs.AuthPipeline` / `ImpersonateAuthPipeline` / `NotAuthPipeline` / `SSOAuthPipeline` / `SSONotAuthPipeline`

Thin Guardian pipeline wrappers using `ArkeAuth.Guardian` or `ArkeAuth.SSOGuardian`. `Impersonate` variant adds a second token verification on the `impersonate-token` header.

### `ArkeServer.Plugs.OAuth`

Reads `:arke_server, ArkeServer.Plugs.OAuth` config, builds a route table `{path, method} → {provider_module, :run_request, options}` at `init/1`, then in `call/2` matches the request path and dispatches to the provider's `handle_request` → `handle_result` → `handle_cleanup`.

```elixir
config :arke_server, ArkeServer.Plugs.OAuth,
  base_url: "lib/auth/signin",
  providers: [
    google:    {ArkeServer.OAuth.Provider.Google,    []},
    apple:     {ArkeServer.OAuth.Provider.Apple,     []},
    facebook:  {ArkeServer.OAuth.Provider.Facebook,  []},
    microsoft: {ArkeServer.OAuth.Provider.Microsoft, []}
  ]
```

---

## Utilities

### `ArkeServer.Utils.QueryFilters`

```elixir
apply_query_filters(query, {logic, negate, base_filters})   # wires :filter into a Query
apply_query_filters(query, _)                                # no-op for nil/other
apply_member_child_only(query, member, true_bool)            # link-filter to member's subtree (depth 10)
get_from_string(conn, filter_string)                         # parse DSL → {:ok, {logic, negate, filters}} | {:error, msgs}
```

The parser is a recursive-descent pass over `and(...)`, `or(...)`, `not(...)`, and the leaf operators. Parameters can be nested via `.` (`customer.name,Ada`) — each segment is resolved by `ParameterManager.get/2`.

### `ArkeServer.Utils.QueryOrder`

```elixir
apply_order(query, nil | [])                    # no-op
apply_order(query, [list_of_order_strings])     # each "param;direction" or "a.b;direction"
apply_order(query, order_string)                # wraps in list
```

Direction is parsed with `String.to_existing_atom/1` — only `:asc` / `:desc` valid.

### `ArkeServer.Utils.QueryProcessor`

```elixir
process_query(query, %{"count_only" => true_ish})  # -> {count, nil}
process_query(query, opts)                          # -> {count, units}  (QueryOrder + QueryManager.pagination)
```

### `ArkeServer.Utils.OneSignal`

```elixir
create_user(member)                                      # register a member as OneSignal user
create_notification(member_or_list, contents, custom_data \\ %{})
```

Uses `ONESIGNAL_APP_ID` and `ONESIGNAL_API_KEY` env vars.

### `ArkeServer.Utils.Apple`

```elixir
client_secret(_config \\ [])   # generates a signed JWT client_secret for Apple OAuth
```

Uses `APPLE_CLIENT_ID`, `APPLE_PRIVATE_KEY_ID`, `APPLE_TEAM_ID`, `APPLE_PRIVATE_KEY` (path or PEM string) env vars. Secret TTL is 180 days.

---

## Mailer macro

```elixir
defmodule MyApp.Mailer do
  use ArkeServer.Mailer

  def signin(conn, member, opts), do: # override per mode
  def signup(conn, params, opts), do: ...
  def reset_password(conn, member, opts), do: ...
end

config :arke_server, :mailer_module, MyApp.Mailer

config :arke_server, MyApp.Mailer,
  adapter: ArkeServer.Swoosh.Adapters.Mailtrap,
  api_key: System.get_env("MAILTRAP_API_KEY"),
  default_sender: {"MyApp", "noreply@myapp.com"}
```

`send_email/1` accepts a keyword list or map with `:to, :from, :subject, :text, :html, :cc, :attachments, :from` plus any provider option (forwarded via `put_provider_option/3`).

`default_sender` is required if an email is sent without a `:from` option — otherwise `send_email` raises.

`signin/signup/reset_password` are stubbed with `{:ok, opts}` in the base macro — override them to actually send.

---

## OAuth strategy macro

```elixir
defmodule MyApp.OAuth.Provider.SomeService do
  use ArkeServer.OAuth.Core

  def handle_request(conn), do: ...   # extract token, validate, put_private :arke_server_oauth → data
  def info(conn),  do: %UserInfo{first_name:, last_name:, email:}
  def uid(conn),   do: "provider-user-id"
  def handle_cleanup(conn), do: put_private(conn, :arke_server_oauth, nil)
end
```

On success, assign `:arke_server_oauth` (an `%AuthInfo{}`) or on failure `:arke_server_oauth_failure`. `OAuthController.handle_client_login/2` dispatches on these assigns.

Provider results surface via two structs:

```elixir
%ArkeServer.OAuth.AuthInfo{uid, provider, strategy, info: %UserInfo{}}
%ArkeServer.OAuth.UserInfo{first_name, last_name, email, phone, birthday}
```

Built-ins depend on env vars: `GOOGLE_CLIENT_ID`, `APPLE_CLIENT_ID`, `FACEBOOK_CLIENT_ID` + `FACEBOOK_CLIENT_SECRET`, plus Microsoft's internal tenant/client setup.

---

## OpenAPI

```elixir
defmodule ArkeServer.ApiSpec do
  @behaviour OpenApiSpex.OpenApi
  def spec, do: %OpenApi{servers:, info:, components:, paths: Paths.from_router(Router)} |> resolve_schema_modules()
end
```

Each controller uses `ArkeServer.Openapi.Spec` to delegate to a paired spec module:

```elixir
defmodule ArkeServer.ArkeController do
  use ArkeServer, :controller
  use ArkeServer.Openapi.Spec, module: ArkeServer.Openapi.ArkeControllerSpec
  ...
end
```

The spec module defines one `*_operation/0` function per action, returning an `%OpenApiSpex.Operation{}`. `ArkeServer.ApiSpec` centralizes reusable parameters (`arke-project-key`, `unit_id`, `limit`, `offset`, `order`, `filter`, …).

Servers list is populated from `Application.get_env(:arke_server, :endpoint_module)` (single module or list). Defaults to `http://localhost:4000`.

---

## Application config reference

| Key | Type | Purpose |
|---|---|---|
| `:arke_server, ArkeServer.Endpoint` | keyword | Standard Phoenix endpoint config — `:secret_key_base`, `:url`, `:http`, `:render_errors`, …|
| `:arke_server, :mailer_module` | module | Host-app mailer used by `AuthController` |
| `:arke_server, <MailerModule>` | keyword | Swoosh mailer config: `:adapter`, `:api_key`, `:default_sender`, … |
| `:arke_server, :endpoint_module` | module \| [module] | OpenAPI server URLs — taken from `endpoint_module.struct_url()` |
| `:arke_server, ArkeServer.Plugs.OAuth` | keyword | `:providers`, `:base_url` |
| `:arke_server, :ecto_repos` | [ArkePostgres.Repo] | For `mix ecto.*` aliases |

Plus the standard `:arke` (`persistence`) and `:arke_auth` (`ArkeAuth.Guardian`) config.

---

## Environment variables

Read at runtime (not compile time):

- `AUTH_MODE` — `"default"` or `"otp_mail"`.
- `APP_REVIEW_EMAIL`, `APP_REVIEW_CODE` — review-mode bypass list.
- `RESET_PASSWORD_ENDPOINT` — base URL for reset emails (the token is appended).
- `ONESIGNAL_APP_ID`, `ONESIGNAL_API_KEY`.
- `GOOGLE_CLIENT_ID`, `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_PRIVATE_KEY_ID`, `APPLE_PRIVATE_KEY`, `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`.
- Plus all `arke_postgres` DB vars: `DB_NAME`, `DB_HOSTNAME`, `DB_USER`, `DB_PASSWORD`.

---

## What's NOT in this package

Search elsewhere for:
- Unit struct, query DSL, CRUD pipeline, managers, lifecycle hooks → `arke`
- Ecto repo, migrations, SQL translation → `arke_postgres`
- `ArkeAuth.Guardian`, `ArkeAuth.Core.{Auth, User, Otp}`, `ArkeAuth.Utils.Permission` → `arke_auth`
- React / Next.js components → frontend packages
