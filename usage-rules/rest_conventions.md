# REST conventions

- Send `arke-project-key: <project_id>` on EVERY call. Missing header → 401
  `"missing project header"`; unknown project → 401 `"invalid project"`. Only
  `/lib/health/*`, `/lib/doc/*`, `/lib/arke_project/*` and
  `/lib/arke_dev_function/*` are exempt.
- Send `Authorization: Bearer <access_token>` unless the endpoint has a public
  permission. Tokens come from `POST /lib/auth/signin`.
- Every response is enveloped: `{"content": ..., "messages": [...]}`. Lists
  arrive as `{"content": {"items": [...], "count": n}}`. Deletes return 204
  with an empty body. Unit creation returns **200**; link and parameter
  creation return **201**.
- Status codes: 400 validation/filter errors, 401 project/auth failures, 402
  subscription inactive, 403 forbidden, 404 not found, 410 expired OTP.
- Core surface:

  ```
  POST   /lib/auth/signin                              {"username","password"}
  POST   /lib/auth/:arke_id/signup
  POST   /lib/auth/refresh
  POST   /lib/:arke_id/unit                            create unit
  GET    /lib/:arke_id/unit                            list/filter units
  GET    /lib/:arke_id/unit/:unit_id                   read unit
  PUT    /lib/:arke_id/unit/:unit_id                   update unit
  DELETE /lib/:arke_id/unit/:unit_id                   -> 204
  GET    /lib/:arke_id/struct                          arke structure (form schema)
  GET    /lib/:arke_id/count
  POST   /lib/:a/unit/:u/link/:link_id/:a2/unit/:u2    create link -> 201
  PUT    /lib/:a/unit/:u/link/:link_id/:a2/unit/:u2    update link ("metadata" key REQUIRED)
  DELETE /lib/:a/unit/:u/link/:link_id/:a2/unit/:u2    delete link
  GET    /lib/:a/unit/:u/link/:direction               link walk (child|parent)
  GET    /lib/group/:group_id/{arke,struct,unit}       group endpoints
  GET|POST /lib/:arke_id/function/:name                arke function
  GET|POST /lib/:arke_id/unit/:unit_id/function/:name  unit function
  GET    /lib/doc/swaggerui                            SwaggerUI
  ```

- JSON body keys are converted with `String.to_existing_atom` — a key that is
  not a loaded parameter atom raises (500). Seed the project
  (`mix arke.seed_project --project <id>`) before hitting the API.
- Multipart uploads land on normal unit create/update (40 MB cap).
- Do NOT use the `/lib/parameter/*` routes — all four actions are stubs, the
  GET crashes, and their permission check is disabled.
- There is no built-in bulk-import (xlsx) endpoint — add your own controller
  calling the arke `import/1` function.
- Prefer explicit link create/delete routes over updating a `:link` parameter
  with PUT — link-parameter updates recreate the underlying rows and a
  mid-flight error can drop the old link without creating the new one.
- Arke/unit/group function return values map to responses:
  `{:file, binary, filename}` → download; `{:error, msg, status}` → that
  status; `{:error, msg}` → 404; `{:ok, content, status}` → JSON; anything
  else → 200.
- `/lib/arke_project/*` (project CRUD) is pinned to the `arke_system` project,
  requires a super-admin token, and is slated for removal — do not build new
  tooling on it.
