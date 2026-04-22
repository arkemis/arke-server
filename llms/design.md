# Design — Why It's Shaped This Way

Rationale behind the load-bearing decisions in arke_server. Useful for:
- **Devs** making sense of unexpected behavior ("it's this way because…")

These are architectural commitments. Changing them cascades through the codebase.

---

## Why Phoenix (and not just Plug)

**The choice:** ArkeServer is a full `Phoenix.Endpoint` + `Phoenix.Router` + controller tree, even though it serves only JSON and has no views, templates, or LiveView.

**What this buys:**
- Router DSL, pipelines, and `pipe_through` give a clean composable authorization story.
- First-class integration with Guardian (`arke_auth`), OpenApiSpex, Swoosh, and the broader Elixir ecosystem.
- Free telemetry hooks for requests, plus the Phoenix community's patterns (`use ArkeServer, :controller`) for extension.
- Host apps can `forward` into this router from their own Phoenix app without adapter glue.

**The cost:**
- Pulls in `plug_cowboy`, `phoenix_html` (transitively for `:browser` pipeline), and session infrastructure that a pure-JSON API doesn't strictly need.
- `Phoenix.Controller` + `Plug.Conn` split is idiomatic but leaves library authors wondering which to import.

**When to revisit:** if dropping Phoenix in favor of a minimal Plug stack would meaningfully reduce startup time or dependency surface. In practice, the router DSL has been the single biggest ergonomic win and keeping it is worth the overhead.

---

## Why a single `/lib` prefix

**The choice:** every route is nested under `/lib`, with the rest of the URL structure (`/:arke_id/unit/:unit_id/...`) following from resource identity.

**What this buys:**
- Host apps can route everything else (their own endpoints, static files, admin tools) alongside the Arke API without path collisions.
- Easy to reverse-proxy or version-prefix: put `/v1` in front of `/lib` at the proxy.
- Mirrors the `arke` Hex naming — the "library" API lives at `/lib`, other concerns can live at `/api`, `/admin`, `/`, etc.

**The cost:**
- Redundant prefix for standalone deployments (the server's whole job is the library API).
- The prefix is hardcoded in the router — switching to `/api` is a source change, not a config.

**When to revisit:** if a future version configures the prefix. This could be done with a `scope Application.get_env(:arke_server, :prefix, "/lib")` at router-compile time.

---

## Why URL-path resource identity, not REST nesting

**The choice:** resources are identified by their URL path segments (`:arke_id`, `:unit_id`, `:arke_parameter_id`) rather than via query parameters or structured nested resources.

- `/lib/:arke_id/unit/:unit_id` rather than `/lib/units/:unit_id?arke_id=...`.
- `/lib/:arke_id/unit/:arke_unit_id/link/:link_id/:arke_id_two/unit/:unit_id_two` for link CRUD — explicit on both ends of the edge.

**What this buys:**
- URLs carry full type context, making them usable as stable references.
- Permission checks can be driven off `conn.path_params["arke_id"]` without decoding bodies.
- The `Permission` plug can make an access decision before the body is even parsed.

**The cost:**
- Verbose URLs for graph operations. Link CRUD URLs are 8-deep.
- Some operations need both sides' types (even though `parent_id`/`child_id` alone would suffice for lookup), adding redundancy.

**When to revisit:** if graph-heavy clients start hand-writing URLs. A compact `/lib/link/:link_id` endpoint could coexist without replacing the verbose form.

---

## Why pipelines compose instead of nest

**The choice:** Related routes are grouped under shared `pipe_through` calls at the scope level rather than per-route. The pipeline list grows as you go deeper in the router.

```elixir
pipe_through [:openapi]
  # auth routes
  pipe_through [:project, :auth_api]
    # group + arke routes
    pipe_through [:get_unit]
      # unit-level routes
```

**What this buys:**
- Most routes share most of their pipeline — defining them once is DRY.
- Pipelines form a natural staircase matching the request's information progression (project → member → unit).
- Adding a new route under an existing scope Just Works — it inherits the expected plugs.

**The cost:**
- Hard to see a route's full pipeline at a glance — you have to trace `pipe_through` calls above it.
- Inserting a route under a different pipeline requires a new scope, which fragments the router file.
- Different pipelines are not documented on a per-route basis; the router is the source of truth.

**When to revisit:** if the router grows past ~400 lines, flattening with explicit `pipe_through` per scope becomes clearer.

---

## Why the `arke-project-key` header instead of a subdomain or path segment

**The choice:** Multi-tenancy is conveyed by a request header. `GetProject` reads it, resolves the `arke_project` Unit in `:arke_system`, assigns the project atom, and every downstream query uses it.

**What this buys:**
- URLs are tenant-agnostic — the same `/lib/person/unit` works for every project.
- Cross-origin clients can use different project keys without CORS or domain routing changes.
- Changing projects at the client is one header swap, not a domain / subdomain switch.
- Health / docs / system routes are naturally exempt (no header, no plug).

**The cost:**
- Logs don't show which project a request is for without custom instrumentation.
- Developers hit "missing project header" errors constantly on first use.
- Easy to accidentally query the wrong project if the client sends the wrong key.

**Compared to subdomains:** subdomains bake tenancy into DNS/TLS and are great for isolation boundaries but heavier to set up. The header is the lighter-weight choice consistent with "project is data, not infrastructure."

**When to revisit:** if cross-tenant data leaks become a real concern. Moving to subdomains or path-prefix tenancy would make it harder to accidentally issue cross-project requests.

---

## Why `Permission` runs before authentication

**The choice:** the `Permission` plug attempts public permission first, and only falls through to `AuthPipeline` if public is denied. The pipeline is `:auth_api`, which is really "authorize, authenticating only if needed."

**What this buys:**
- Public resources (catalog pages, published docs) skip the auth round-trip entirely.
- A single plug decides "public, or member?" — controllers don't branch.
- Invalid tokens on a public endpoint don't cause a 401 — they're ignored if the resource is public.

**The cost:**
- Surprising for anyone expecting a conventional "authenticate-then-authorize" pipeline.
- Controllers must defensively handle `ArkeAuth.Guardian.get_member(conn) == nil` even though they're in a `:auth_api`-piped scope.
- `{{arke_member}}` substitution inside a *public* permission filter has no member to substitute — silent mis-parse.

**Compared to auth-first:** auth-first would be simpler but every public request would still cost a JWT verification. The public-first ordering is optimized for zero-auth-cost public traffic.

**When to revisit:** if the misuse rate of `{{arke_member}}` in public permissions becomes a bug source, the plug could error-out rather than silently mis-substitute.

---

## Why there's a `ResponseManager` wrapping every response

**The choice:** every controller ends with `ResponseManager.send_resp(conn, status, data, messages \\ [])` rather than raw `Phoenix.Controller.json/2` or `send_resp/3`.

**What this buys:**
- Single source of truth for the envelope shape: `{content, messages}` or `{content: {items, count}, messages}`.
- Messages / errors live at the same JSON path regardless of response type — clients can have one parser.
- Errors from anywhere in the pipeline (parse errors, permission rejections, validation failures) surface uniformly.
- 204 responses are explicit (`send_resp(conn, 204)`) rather than a special case of `send_resp/5`.

**The cost:**
- Controllers can't easily deviate from the envelope if a client expects something else.
- The envelope forces `count` for list responses, which is computed server-side even when the client doesn't need it.
- Error shapes are looser than the happy-path shape — `messages` is always a list but of variable map shapes.

**When to revisit:** if a consumer needs a different shape (e.g. GraphQL-style data/errors split), this would be the extension point. Don't weaken it — loosening the envelope makes client code harder, not easier.

---

## Why the filter DSL is a string, not JSON

**The choice:** `?filter=and(gte(age,23),contains(name,Ada))` rather than `?filter={"and": [{"gte": {"age": 23}}, ...]}`.

**What this buys:**
- Readable in log output and browser URL bars.
- No JSON encoding/decoding overhead on the query string.
- Typable by hand.
- Compact — permits deep trees without escape-hell.

**The cost:**
- URL character limits in some clients/proxies (~2000 chars).
- Custom grammar that clients must generate — no standard parser.
- Values are always strings (the server coerces per parameter type); you can't pass structured arguments cleanly.
- The `in(param, (a,b,c))` syntax is ugly because parentheses are overloaded.

**Compared to JSON:** JSON is more standard but less ergonomic in URLs. Query builders in TypeScript / Python clients need similar code either way — the string form is more human-friendly for manual testing.

**When to revisit:** if permission filters (stored in the DB) start to look unwieldy, adding a JSON-compatible `filter_json` endpoint alongside the string one would be a small addition.

---

## Why there are two filter parsers

**The choice:** `BuildFilters` has a regex-based `get_conditions/5` and `QueryFilters` has a recursive-descent `get_from_string/2`. Both exist; both are called.

**What this buys:**
- The newer recursive parser handles arbitrarily nested logical expressions correctly — the regex one could not.
- Kept side-by-side rather than deleted outright to avoid breaking anything that depended on the old behavior.

**The cost:**
- Duplicated operator lookup (`get_operator/1`), duplicated parse logic, duplicated error messages.
- Confusion about which parser runs where.
- Inconsistent behavior for edge-case inputs (malformed filters parse differently).

**When to revisit:** now, ideally. The recursive-descent parser can subsume the older one entirely. Removing `get_conditions/5` (or at least delegating it to `QueryFilters`) would be a clear refactor win.

---

## Why OAuth providers are code modules, not config

**The choice:** each OAuth provider is a module using `ArkeServer.OAuth.Core`. Configuration (`providers: [google: {...}]`) names the module; the module implements the protocol.

**What this buys:**
- Providers can express arbitrary token-validation logic (Apple's nonce check, Google's cert rotation, Microsoft's two-token flow).
- No DSL to learn — it's just Elixir behaviours.
- New providers are additive; adding one doesn't touch existing code.
- Easy to test a provider in isolation.

**The cost:**
- Boilerplate per provider — the four built-ins are 80% identical structure.
- Client protocols differ per provider (query params vs body params, single token vs nonce+token vs id_token+access_token), so the handler can't be uniform.

**Compared to a config-driven approach:** you'd need a constraint language to express Apple's nonce validation or Microsoft's dual-token exchange. That language would end up Turing-complete, at which point just using Elixir is simpler.

**When to revisit:** only if the number of providers explodes — even then, most providers are OAuth2 with minor differences, and a shared helper would capture most of it.

---

## Why OpenAPI specs are per-controller spec modules, not inline annotations

**The choice:** `use ArkeServer.Openapi.Spec, module: ArkeServer.Openapi.ArkeControllerSpec` — the controller points at a spec module that defines one `<action>_operation/0` per action. The controller source is unchanged by spec maintenance.

**What this buys:**
- Controllers stay readable — OpenApiSpex annotations can be verbose.
- Spec modules can be edited without recompiling controllers.
- Host apps can swap in their own spec modules if they need a different OpenAPI surface.

**The cost:**
- Spec files duplicate action names and arities — easy to drift out of sync with the controller.
- No compile-time check that the spec module has an operation for every action.

**When to revisit:** if drift becomes common, a `@behaviour` or macro-generated operation hook could enforce coverage.

---

## Why controllers directly call `Arke.*` instead of going through a service layer

**The choice:** every controller action builds its `%Query{}` via `Arke.QueryManager`, calls `Arke.StructManager.encode/2` inline, and uses `LinkManager` / `ArkeManager` directly.

**What this buys:**
- Thin controllers — most actions are ~20 lines.
- No indirection between HTTP and the domain — easy to reason about what a route does.
- Reuse: `QueryFilters`, `QueryProcessor` are the shared helpers; controllers never repeat the pagination+count dance.

**The cost:**
- Query-building logic is partially in the controller (e.g. coordinates filter in `ArkeController`) rather than in a dedicated module.
- Testing a "get all persons with filter" behavior requires a full request conn.
- If two routes need the same complex query, it gets copy-pasted.

**When to revisit:** if controllers grow past ~300 lines or the same query appears in three places. For now, the flatness is a readability win.

---

## Why the mailer is an overridable macro, not a behaviour

**The choice:** `use ArkeServer.Mailer` injects `signin/3`, `signup/3`, `reset_password/3`, and `send_email/1`, all `defoverridable`. Host apps supply their own mailer module via `:mailer_module` config.

**What this buys:**
- Host app gets working stubs for free — nothing breaks if you haven't overridden anything.
- Swoosh's `use Swoosh.Mailer` is already a macro, so this composes naturally.
- Email sending is an opt-in extension rather than a required integration.

**The cost:**
- No compile-time guarantee that a host app's overrides have the right signatures.
- Stubs returning `{:ok, opts}` silently do nothing — easy to think you're sending mail when you aren't.
- Email-sending failures don't propagate; the auth flow reports success even if the OTP email never left.

**Compared to `@behaviour`:** a behaviour gives compile-time signature checking and explicit opt-in. The macro flavor won because it lets host apps pick up default behavior without a full implementation.

**When to revisit:** if email delivery reliability becomes a correctness issue. A `@behaviour` plus a supervised delivery worker would be a better fit for production billing / auth emails.

---

## Decisions explicitly left flexible

- **Mailer adapter** — configurable via Swoosh. Mailtrap and OneSignal shipped; anything Swoosh-compatible works.
- **OAuth providers** — four built-in, trivially extensible.
- **Permission model** — the filter template DSL is expressive enough to encode most ownership/sharing rules; `child_only` handles tree-scoped access.
- **Endpoint config** — host apps supply their own; this package provides the `ArkeServer.Endpoint` as a starting point.

## Decisions that are non-negotiable (by current design)

- **`/lib` prefix.** Hardcoded.
- **`arke-project-key` header.** The multi-tenant identity mechanism.
- **JWT via `arke_auth` + Guardian.** No other auth scheme is supported.
- **Response envelope shape.** Clients depend on it.

If a roadmap conversation touches any of these four, treat it as a breaking change requiring coordinated client + server rollout.
