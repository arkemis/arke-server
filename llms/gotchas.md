# Gotchas — Sharp Edges

Operational surprises you'll hit when working with arke_server. These are distinct from design rationale (see [design.md](design.md) for the "why"); this file is the "what trips people up."

---

## The `arke-project-key` header is near-mandatory

Nearly every route piped through `:project` halts with 401 if the `arke-project-key` header is missing. The exceptions are:

- `/lib/health/*`
- `/lib/doc/*`
- `/lib/arke_project/*` (uses `:auth_api` only — no `:project`; its plug internally forces `arke_project = :arke_system`)
- `/lib/arke_dev_function/*` (same)

**Symptom:** Every request returns `401 {"messages": [{"context": "auth", "message": "missing project header"}]}`.

**What to do:** always include `arke-project-key: <project_id>` on client requests, even public ones (public endpoints still need the project for permission resolution).

---

## `String.to_existing_atom` is everywhere — and it silently fails

The server calls `String.to_existing_atom/1` in many hot paths:

- Body params → `data_as_klist/1` (keys become atoms).
- Path params (`arke_id`, `direction`, order direction, function_name) → atomized for manager lookups.
- Group IDs in `GroupController`.

If the atom doesn't exist (typically because the Arke module isn't compiled in, or the project wasn't seeded), the call raises `ArgumentError`. Some sites catch this, others don't.

**Symptom:** Random `ArgumentError: errors were found at the given arguments` or 500s on requests referencing unknown Arkes / parameters.

**What to do:**
- Ensure compile-time Arke modules are in your host app's deps (`Code.ensure_loaded?(MyApp.Person)`).
- Run `mix arke.seed_project --project <id>` after adding a new Arke to a project.
- When you see a 500 on a request that touches a dynamic identifier, check whether that atom has ever been materialized.

---

## `order` direction and link `direction` must be `asc/desc` or `child/parent`

`QueryOrder.apply_order` parses order strings with `String.to_existing_atom/1`:

```
?order[]=name;up    # 500 ArgumentError — "up" isn't an existing atom
?order[]=name;asc   # OK
```

Same for topology direction:

```
GET /lib/.../link/children   # 500 — "children" ≠ :child
GET /lib/.../link/child      # OK
```

**Symptom:** 500 error with `ArgumentError` from `String.to_existing_atom`.

**What to do:** use exactly `asc` / `desc` for ordering, exactly `child` / `parent` for direction.

---

## `load_*` flags are opt-in *and* require string `"true"`

```
?load_links=true     # OK
?load_links=1        # FALSE — the check is exactly `== "true"`
?load_links          # FALSE — missing param defaults to "false"
```

See `ArkeController` `get_unit` / `get_all_unit` / `create` / etc.

**What to do:** always pass the literal string `true`. Everything else is treated as false.

---

## `:filter` and `:permission_filter` are composed, not replaced

`QueryFilters.apply_query_filters/2` is called twice on most list endpoints — once with the user-supplied `?filter=`, once with the permission filter. Both are ANDed into the query (via `QueryManager.and_` / `or_` keyed on the filter's logic).

If a permission filter restricts to `eq(owner,{{arke_member}})` and the user's `?filter=eq(owner,other_user)` is non-matching, the intersection is empty — you get no results. This is correct behavior, but can be confusing when debugging.

**What to do:** when a query returns unexpectedly empty results for an authenticated user, check what `conn.assigns[:permission_filter]` resolved to. Temporarily bypass by testing with a super_admin member.

---

## The filter DSL has two parsers — and the old one is still wired

There are two filter-parsing implementations:

- `ArkeServer.Plugs.BuildFilters.get_conditions/5` — flat, regex-based, older. Used for the legacy logic-plus-negate case.
- `ArkeServer.Utils.QueryFilters.get_from_string/2` — recursive-descent, nested, newer. Used by `BuildFilters.call/2` and `Permission`.

The recursive-descent parser supports proper nesting (`or(eq(a,1),and(eq(b,2),eq(c,3)))`). The older one doesn't fully handle deep nesting.

**Symptom:** A deeply nested `?filter=` works, but the same expression inside a permission filter (parsed by a different path) fails or misbehaves.

**What to do:** when writing permissions, keep nesting shallow. For request-time filters, the full recursive-descent grammar is supported.

---

## Permission plug: the public-then-private dance

When a route is pipelined through `:auth_api`, `Permission` runs *before* auth. It:

1. Attempts public permission with no member. If permitted, auth never runs — `conn.assigns[:permission_filter]` is set, any `:permission_filter.filter` using `{{arke_member}}` won't be substituted.
2. Only if public fails does it invoke `AuthPipeline`, then member permission.

**Surprises:**
- If you rely on `ArkeAuth.Guardian.get_member(conn)` inside a public-accessible endpoint, it returns `nil`.
- A filter template with `{{arke_member}}` on a public permission becomes a literal string — and then probably errors on parameter lookup.
- Order of permission checks matters: a broad public permission masks a narrower member-scoped one.

**What to do:**
- Design permissions as public *or* member-scoped, not both.
- In controller actions that must always have a member, call `ArkeAuth.Guardian.get_member(conn, impersonate: true)` defensively and short-circuit on `nil`.

---

## Subscription / payment required (402)

The `Permission` plug returns **402 Payment Required** when:
- Public permission fails, *and*
- Member permission fails, *and*
- The member's `data.subscription_active` is `false`.

This is opinionated behavior for SaaS apps with subscription gates. If you don't use a `subscription_active` field on your member Arke, members always get 403 instead — `Map.get(member.data, :subscription_active)` returns `nil`, not `false`, and the 402 branch doesn't fire.

**What to do:** be aware that 402 can be issued even if your app has no billing. Keep the member Arke's schema consistent.

---

## Impersonation requires *both* tokens

`ImpersonateAuthPipeline` verifies `Authorization: Bearer <admin>` **and** `impersonate-token: Bearer <target>`. Missing either → 401.

`ArkeAuth.Guardian.get_member(conn, impersonate: true)` prefers the impersonate target; `get_member(conn)` without the option returns the real admin.

**What to do:** controllers that make decisions "on behalf of" need to use `impersonate: true`. The codebase is inconsistent about this — audit when adding a new endpoint under impersonation flows.

---

## OTP flows require `:mailer_module` — otherwise codes are generated but never sent

`AuthController` handles `AUTH_MODE="otp_mail"` by calling `mailer_module().signin(...)`. If you haven't configured `:mailer_module`, the call is `nil.signin(...)` → `UndefinedFunctionError`.

**Symptom:** 500 at signin/signup/recover_password when `AUTH_MODE` is set to `otp_mail`.

**What to do:** always configure `:mailer_module` whenever `AUTH_MODE` is not `default`. In dev, a stub mailer that logs codes to console is enough.

---

## Review codes ship by default

If `APP_REVIEW_EMAIL` is unset, the check returns an empty list and the short-circuit never fires. **But** `APP_REVIEW_CODE` has a default of `"1234"`. If you later add `APP_REVIEW_EMAIL` in staging without also overriding `APP_REVIEW_CODE`, the reviewer list can authenticate with `1234`.

**What to do:** always set both in environments where the feature is used.

---

## `ProjectController` is pinned to `:arke_system`

All five `ProjectController` actions hardcode `:arke_system` as the project. You can't reach them to create a project *inside* another project — projects are system-level resources. This is correct by design, but surprising given most routes are project-scoped.

The `Permission` plug's regex-based path extraction has a special case: when the URL path mentions `arke_project`, it forces `conn.assigns[:arke_project] = "arke_system"` before checking permission. So sending `arke-project-key: my_project` on a `/lib/arke_project/*` route is overridden silently.

---

## `:link` parameters propagate deletions

When you `PUT /lib/:arke_id/unit/:id` with a changed `:link` parameter value, the underlying `arke_link` Unit(s) are recreated. If the request errors halfway (for example, one of the link target IDs doesn't exist), you can end up with the old link deleted but the new one not created — silent data loss.

This is an `arke`-level issue (see `arke/llms/gotchas.md#link-parameters-have-side-effects`), but manifests here because PUT requests are the common trigger.

**What to do:** in high-stakes link updates, prefer `POST /lib/.../link/...` (direct `LinkManager.add_node`) so you see the specific failure.

---

## The `ArkeError` → status mapping lives in `ArkeServer`

```elixir
defimpl Plug.Exception, for: Arke.Errors.ArkeError do
  def status(%Arke.Errors.ArkeError{type: :unauthorized}), do: 401
  def status(%Arke.Errors.ArkeError{type: :forbidden}),    do: 403
  def status(%Arke.Errors.ArkeError{type: :not_found}),    do: 404
  def status(_),                                           do: 400
end
```

If you `raise Arke.Errors.ArkeError, message: "...", type: :conflict` elsewhere, it becomes a 400 — the mapping is closed. Add a new clause here if you need more granular status codes.

---

## Corsica `origins: "*"` and `allow_headers: :all` are dev-friendly, not prod-friendly

```elixir
plug Corsica, origins: "*", allow_headers: :all
```

This is in `Endpoint` unconditionally. In production, override the endpoint config to constrain origins, or wrap the endpoint and prepend a tighter Corsica plug.

---

## Session signing salt is hardcoded

```elixir
@session_options [store: :cookie, key: "_arke_server_key", signing_salt: "Z1CpNd1R"]
```

This is in the library source. If you use cookies (currently only for the commented-out SSO browser flow), override `config :arke_server, ArkeServer.Endpoint, secret_key_base:` — it's the real protection — but be aware the salt is public.

---

## `get_parameter_value` and siblings are stubs

`ParameterController` has four actions wired to the router but with placeholder bodies. `get_parameter_value` returns `{count: 0, items: []}` unconditionally. The other three return empty success responses.

**What to do:** don't build frontend flows on these endpoints. Implement them in your own controller, or contribute the implementation upstream.

---

## Route order matters for `pipe_through`

The router uses top-level `pipe_through` calls between scopes:

```elixir
scope "/lib", ArkeServer do
  scope "/health" do ... end         # no pipelines
  pipe_through [:openapi]
  scope "/auth" do ... end            # :openapi + per-scope
  scope "/arke_project" do ... end    # :openapi + :auth_api
  scope "/arke_dev_function" do ... end
  pipe_through [:project, :auth_api]
  scope "/group/:group_id" do ... end # :openapi + :project + :auth_api
  pipe_through [:get_unit]
  # all routes below here get :openapi + :project + :auth_api + :get_unit
end
```

Adding a route at the bottom automatically inherits `[:openapi, :project, :auth_api, :get_unit]`. Routes added earlier don't get the later pipelines.

**What to do:** when adding routes, pick the scope block that matches your needed pipelines. Don't insert routes in the middle of a shared scope expecting a different pipeline.

---

## OpenAPI spec caches at module-load time

`ArkeServer.ApiSpec.spec/0` calls `OpenApiSpex.resolve_schema_modules/1` on each invocation, but `OpenApiSpex.Plug.PutApiSpec` caches the result in `conn.private`. Adding new routes or editing a `*ControllerSpec` requires a recompile — `iex> recompile()` won't always pick it up.

**What to do:** if the spec is stale during development, restart the server.

---

## Dev `config/dev.exs` is empty; runtime config lives in your host app

The shipped `config/dev.exs` only re-sets the JSON library. No endpoint config, no DB, no auth. That's because this package is meant to be a dependency — host apps supply their own runtime config. The `config/test.exs` is the most complete template.

**What to do:** for local development of arke_server itself, create a local `config/dev.exs` override outside of git (or copy from `test.exs` and adjust).
