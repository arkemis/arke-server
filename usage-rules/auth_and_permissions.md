# Auth and permissions

- The `Permission` plug is public-first: it checks the PUBLIC permission
  before authenticating, and only falls back to member auth + member
  permission when public access is denied.
- Design each endpoint's permission as public XOR member-scoped. In a
  public-permitted request the member is `nil`, so a `{{arke_member}}`
  placeholder in the permission filter cannot be resolved; the request is
  rejected with 403.
- `{{arke_member}}` in a permission filter string is replaced with the member
  id before parsing. Filter parse errors reject the request with 403; test
  permission filters explicitly against real requests.
- 402 is returned only when `member.data.subscription_active == false`
  (missing field → 403 path instead).
- Impersonation requires BOTH headers: `Authorization` (admin token) and
  `impersonate-token` (target token). Server-side, read the target with
  `ArkeAuth.Guardian.get_member(conn, impersonate: true)`.
- `AUTH_MODE` selects the flow: `"default"` (username+password) or
  `"otp_mail"` (credentials → emailed OTP → resubmit with `otp`).
  The configured mode applies to `:super_admin` members too.
- OTP / signup / reset-password mail flows require a configured mailer —
  without it they crash with `UndefinedFunctionError`:

  ```elixir
  config :arke_server, :mailer_module, MyApp.Mailer
  ```

- Reviewer sign-in requires both `APP_REVIEW_EMAIL` and `APP_REVIEW_CODE`.
  There is no default code; wrong guesses are limited to five per username
  in a 15-minute window.
- Authentication errors use `messages` with `context` and `message`. OTP
  verification returns 401 for invalid codes, 410 for expired codes, and 429
  when the attempt limit is reached.
- Microsoft OAuth verifies the token signature against the tenant signing
  keys and rejects a token signed with an unpublished key.
