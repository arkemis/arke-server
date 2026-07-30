# Rules for working with ArkeServer

## Understanding ArkeServer

ArkeServer is the Phoenix HTTP/JSON layer of the Arke framework. It exposes the
runtime-defined Arke domain model (Arkes, Units, Parameters, Groups, Links) as
a multi-tenant REST API mounted under the `/lib` prefix: every route translates
an HTTP request into Arke core calls and serializes the result through a single
response envelope. It owns no persistence (that is `arke_postgres`) and no auth
core (that is `arke_auth`/Guardian) — it contributes routing, plug pipelines,
a string filter DSL, OpenAPI specs with SwaggerUI, pluggable client-side OAuth
strategies, and Swoosh mailer hooks.

Four contracts are non-negotiable — never work around them: the `/lib` route
prefix, the `arke-project-key` header, Guardian-only auth, and the
`{"content": ..., "messages": [...]}` response envelope.

Read the topic rules in `usage-rules/` before integrating or extending it.
