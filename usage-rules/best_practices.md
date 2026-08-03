# Best practices

- Test with `use ArkeServer.ConnCase`: it provides `@endpoint`,
  `build_authenticated_conn/1` (sets `authorization` +
  `arke-project-key: test_schema`) and an Ecto SQL sandbox checkout. The
  `mix test` alias drops/creates the DB, runs `arke_postgres.init_db` and
  creates the `test_schema` project.
- Restart the server after router or OpenAPI-spec changes — the spec is
  cached per-process; `recompile()` is not enough.
- Do not serve `/lib/doc/openapi` from a production release — it reads
  `Mix.Project.config()`, which is unavailable in releases, and raises.
- Debug empty or surprising results by inspecting the assigns:
  `conn.assigns[:arke_project]`, `[:filter]`, `[:permission_filter]`,
  `[:unit]` — most issues are a wrong project atom or an ANDed permission
  filter.
- Version pins are tight and load-bearing: `phoenix ~> 1.7.0`,
  `arke ~> 0.6.0`, `arke_postgres ~> 0.5.0`, `arke_auth ~> 0.4.4`. Do not mix
  with older arke releases.
- Nested filters/order (dotted paths), `count_only` and `load_files` require
  arke_server ≥ 0.4.x; deep filter nesting requires 0.5.x.
- Ignore the commented-out server-side OAuth redirect routes and the legacy
  `:ueberauth_*` handling in `OAuthController` — dead code.
- If a response comes back as plain-text 400 `"invalid data format"`, the
  content failed JSON encoding — check for non-encodable values in unit data.
