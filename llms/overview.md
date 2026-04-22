# Overview — Mental Model

## What problem ArkeServer solves

`arke` gives you a schema registry + CRUD pipeline + query DSL, but it's framework-agnostic and does no I/O. ArkeServer is the Phoenix-based HTTP layer that makes `arke` usable as a remote service: multi-tenant routing, JWT auth, permission checks, a filter query string syntax, file downloads, OpenAPI docs, OAuth for social login, and email/push hooks for auth flows.

If you think of `arke` as the kernel, ArkeServer is the userland REST API.

## Request lifecycle

Every authenticated request funnels through the same sequence:

```
HTTP request
  │
  ▼
ArkeServer.Endpoint           Phoenix endpoint: static, parsers, Corsica (CORS), sessions
  │
  ▼
ArkeServer.Router             Pipelines compose by scope:
  │                             :api              ← NotAuthPipeline (public endpoints)
  │                             :auth_api         ← Permission plug (permission + auth fallback)
  │                             :tmp_auth_pipe    ← AuthPipeline (bare auth, no permissions)
  │                             :project          ← GetProject + BuildFilters
  │                             :get_unit         ← GetUnit (loads conn.assigns[:unit])
  │                             :oauth            ← OAuth (provider route dispatch)
  │                             :sso_auth_api     ← SSOAuthPipeline (SSO JWT)
  │                             :openapi          ← PutApiSpec
  ▼
Controller action             Calls Arke.QueryManager / LinkManager / StructManager
  │
  ▼
ResponseManager.send_resp     Wraps result in `{content:, messages:}` / `{items:, count:, messages:}`
  │
  ▼
JSON response
```

The five conn.assigns that matter downstream of the pipelines:

| Assign | Set by | Used for |
|---|---|---|
| `:arke_project` | `GetProject` | project atom passed to every `QueryManager` call |
| `:permission_filter` | `Permission` | `%{filter, child_only}` applied to every query |
| `:filter` | `BuildFilters` | parsed `?filter=` string as `{logic, negate, base_filters}` |
| `:unit` | `GetUnit` | the Unit resolved from `:unit_id` / `:arke_unit_id` path params |
| Guardian resource | `AuthPipeline` | the authenticated member (access via `ArkeAuth.Guardian.get_member(conn)`) |

## Route namespaces

All routes live under `/lib`. There are four logical zones:

### 1. Public (no project, no auth)

- `GET /lib/health/ready` / `live` / `start` — k8s probes.
- `GET /lib/doc/swaggerui` / `openapi` — docs.

### 2. Auth (needs project, may or may not need member auth)

Under `/lib/auth`:
- `POST /signin`, `POST /:arke_id/signup`, `POST /refresh`, `POST /recover_password`, `POST /reset_password[/:token]`.
- `POST /verify`, `POST /change_password` — authenticated (pipeline: `:auth_api`).
- `POST /signin/:provider` — OAuth login via client-side token. The `:oauth` pipeline dispatches to `ArkeServer.OAuth.Provider.Google|Apple|Facebook|Microsoft`.
- `POST /:member/:provider` — SSO-create-member flow (pipeline: `:sso_auth_api`).

### 3. Project management (system project only)

Under `/lib/arke_project`:
- `GET/POST/PUT/DELETE /unit[/:unit_id]` — CRUD on the `arke_project` Arke. Creating a Unit here calls the `on_create` hook of `Arke.Core.Project`, which in turn calls `persistence[:arke_postgres][:create_project]` to provision the backend schema.

Uses `:auth_api` pipeline (member must be authenticated & permitted).

### 4. Generic Arke / Unit / Topology / Parameter / Group (project-scoped)

This is the bulk of the API. Under `/lib` with pipelines `[:project, :auth_api, :get_unit]`:

- **Arke level** (`/lib/:arke_id/...`) — CRUD on any Arke, plus `struct`, `group`, `count`, `function`.
- **Unit level** (`/lib/:arke_id/unit/:unit_id/...`) — get/update/delete a specific Unit, call a per-unit function.
- **Topology** (`/lib/:arke_id/unit/:arke_unit_id/link/:direction`, `/link/:link_id/:arke_id_two/unit/:unit_id_two`) — graph walks + link CRUD.
- **Parameter** (`/lib/:arke_id/parameter/:arke_parameter_id`) — add / update parameter metadata on an Arke (creates/updates an `arke_link` of type `"parameter"`).
- **Group** (`/lib/group/:group_id/...`) — list Arkes / Units in a Group, call a group function.
- **Global search** (`/lib/unit`) — project-wide unit search.

See [reference.md](reference.md#routes-at-a-glance) for the exact route table.

## Query string conventions

Every list endpoint accepts the same query params, parsed by:

- `BuildFilters` / `ArkeServer.Utils.QueryFilters` — the `?filter=` DSL.
- `ArkeServer.Utils.QueryOrder` — the `?order[]=` array.
- `ArkeServer.Utils.QueryProcessor` — orchestrates pagination + count-only.

### Filter DSL

```
filter=and(gte(age,23),contains(name,string))
filter=or(eq(role,admin),and(gt(age,30),isnull(deleted_at)))
filter=not(in(status,draft,archived))
```

Supported operators (must match the source exactly — all lowercase, all one-to-one with `Arke.Core.Query` operators): `eq`, `contains`, `icontains`, `startswith`, `istartswith`, `endswith`, `iendswith`, `lt`, `lte`, `gt`, `gte`, `in`, `isnull`. Logical combinators: `and`, `or`, `not`.

Nested paths use dot notation inside the parameter position — `eq(customer.name,Ada)` walks the `:customer` link parameter first. Each segment is resolved via `ParameterManager.get/2`.

### Ordering, pagination, load flags

```
?order[]=inserted_at;desc&order[]=name;asc
?offset=40&limit=20
?count_only=true       ← skip the fetch, return just the count
?load_links=true       ← inline-expand :link parameters
?load_values=true      ← expand parameter value metadata
?load_files=true       ← resolve arke_file signed URLs
```

`load_*` flags pass through to `Arke.StructManager.encode/2`.

## Response envelope

`ArkeServer.ResponseManager.send_resp/5` normalizes every body:

- Single resource: `{content: ..., messages: []}`
- List: `{content: {items: [...], count: N}, messages: []}`
- Errors: `{content: nil, messages: [{context, message}, ...]}`
- 204: empty body.

Status codes: `200` on success, `201` on link create / some OAuth flows, `204` on delete, `400` on validation/filter errors, `401` on missing/invalid auth, `402` if the member's `subscription_active` is false, `403` on forbidden, `404` on missing Unit/Arke, `410` for expired OTP.

## The Permission plug

`ArkeServer.Plugs.Permission` (on the `:auth_api` pipeline) is the sharpest part of the request path:

1. Extract `arke_id` / `group_id` / `parameter_id` from path params (or regex the path for system-scoped endpoints).
2. First try **public permission** — `ArkeAuth.Utils.Permission.get_public_permission(arke_id, project)`. If the resource is public for the requested HTTP method, set `:permission_filter` and pass.
3. Otherwise, run `AuthPipeline` (or `ImpersonateAuthPipeline` if `impersonate-token` header present) to authenticate the member.
4. Fetch **member permission** — `get_member_permission(member, arke_id, project)`. If permitted, set `:permission_filter` and pass.
5. If `subscription_active == false` → 402. Else → 403.

The resulting `:permission_filter` is `%{filter: parsed_filter, child_only: bool}` and is applied to every query via `QueryFilters.apply_query_filters/2` (intersected with the user-supplied `?filter=`). `{{arke_member}}` inside a filter template is replaced with the member's ID — how you scope queries to "things owned by the current user."

See [gotchas.md](gotchas.md#permission-plug-the-public-then-private-dance).

## Modules at a glance

```
lib/
├── arke_server.ex              Phoenix use/import macros + Plug.Exception for ArkeError
├── routes.ex                   Runtime-introspected route list (for docs)
└── arke_server/
    ├── application.ex          OTP app: starts Telemetry + Endpoint
    ├── endpoint.ex             Phoenix.Endpoint, static, parsers, CORS, session
    ├── router.ex               All routes + pipelines
    ├── response_manager.ex     Envelope formatting + Jason encode
    ├── telemetry.ex            :telemetry_poller metrics
    ├── controllers/            One per resource (arke, unit, group, …)
    ├── plugs/                  Auth, project, unit, permission, filter, oauth
    ├── utils/                  Filter/order/process parsers, OneSignal, Apple secret
    ├── email_manager/          Swoosh mailer macro + Mailtrap / OneSignal adapters
    ├── oauth/                  Provider strategies + Core dispatch
    ├── openapi/                Per-controller OpenApiSpex operation specs
    └── error_handlers/         Guardian error → 401 JSON
```

## Boundaries

| Concern | Where it lives |
|---|---|
| Schema, CRUD pipeline, query builder, link graph | `arke` (sibling) |
| Postgres persistence, SQL, migrations | `arke_postgres` (sibling) |
| JWT, Guardian, permissions, credential validation | `arke_auth` (sibling) |
| HTTP routes, plugs, request/response shape, OpenAPI, OAuth, mailer | **arke_server** (this package) |

If you find yourself writing SQL, defining a Guardian pipeline, or reaching into ETS directly — you're in the wrong package. Call `ArkeAuth.Guardian.get_member/1`, `Arke.QueryManager.*`, `Arke.LinkManager.*` instead.
