# Upgrading arke_server

## To the auth hardening release (from 0.5.x)

This release requires the matching `arke_auth` release; read its
`UPGRADING.md` first. The points below are what changes on the HTTP side.

### Configuration

`arke_auth` refuses to start without its two secrets. Set them in your
application's `config/runtime.exs`, and in `config/test.exs` for your tests:

```elixir
config :arke_auth, ArkeAuth.Utils.TokenCrypto,
  token_key: System.fetch_env!("ARKE_AUTH_TOKEN_KEY")

config :arke_auth, ArkeAuth.Core.Password,
  pepper: System.fetch_env!("ARKE_AUTH_PASSWORD_PEPPER")
```

### Responses

- `POST /lib/auth/:arke_id/signup` and `POST /lib/auth/signin` in `otp_mail`
  mode answer **429** when a code was sent less than
  `resend_cooldown_seconds` (default 30) ago.
- `POST /lib/auth/recover_password` in `otp_mail` mode answers 200 within the
  cooldown without sending a code, as it does for an unknown email.
- `GET`/`POST /lib/auth/signin` with `token` or `auth_token` consumes a
  temporary token (`ArkeAuth.Core.TemporaryToken`) from the token store. The
  two parameters are aliases: same token, same checks. An unknown, expired or
  used token, or an inactive member, answers 401; a token whose member does
  not exist answers 403 instead of crashing. `auth_token` now refuses
  inactive members too. The member `auth_token` field no longer signs in.
- `POST /lib/auth/recover_password` in `default` mode mails a signed reset
  link; nothing is stored. `POST /lib/auth/reset_password` accepts it once:
  the password change voids it. Links mailed before the upgrade stop
  working. The mailer still receives `mode: "email"`, `endpoint:` and
  `unit:` with `data.token`, `data.expiration` and `data.user_id`.

### Tests

The test suite seeds its projects with `arke.seed_project` and needs a
Postgres reachable through `DB_HOSTNAME`, `DB_NAME`, `DB_USER` and
`DB_PASSWORD` (CI sets them).
