# Auth and permissions

- The `Permission` plug is public-first: it checks the PUBLIC permission
  before authenticating, and only falls back to member auth + member
  permission when public access is denied.
- Design each endpoint's permission as public XOR member-scoped. In a
  public-permitted request the member is `nil`, so a `{{arke_member}}`
  placeholder in the permission filter fails to parse and silently becomes
  **no restriction at all**.
- `{{arke_member}}` in a permission filter string is replaced with the member
  id before parsing; any filter parse error silently disables the filter —
  test permission filters explicitly against real requests.
- 402 is returned only when `member.data.subscription_active == false`
  (missing field → 403 path instead).
- Impersonation requires BOTH headers: `Authorization` (admin token) and
  `impersonate-token` (target token). Server-side, read the target with
  `ArkeAuth.Guardian.get_member(conn, impersonate: true)`.
- `AUTH_MODE` selects the flow: `"default"` (username+password) or
  `"otp_mail"` (credentials → emailed OTP → resubmit with `otp`).
  `:super_admin` members always use the default mode.
- OTP / signup / reset-password mail flows require a configured mailer —
  without it they crash with `UndefinedFunctionError`:

  ```elixir
  config :arke_server, :mailer_module, MyApp.Mailer
  ```

- If you set `APP_REVIEW_EMAIL`, always set `APP_REVIEW_CODE` too — it
  defaults to `"1234"`.
- Auth failures always return 401 with
  `{"messages":[{"context":"auth","message":...}]}`.
- Do not rely on Microsoft OAuth signature validation in production — it is
  known-broken (accepts invalid signatures) until fixed.
