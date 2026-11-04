defmodule ArkeServer.Plugs.AuthRateLimitTest do
  use ArkeServer.ConnCase, async: false

  @config ArkeServer.Plugs.AuthRateLimit

  setup do
    previous = Application.get_env(:arke_server, @config)
    on_exit(fn -> Application.put_env(:arke_server, @config, previous) end)
    :ok
  end

  defp configure(opts),
    do: Application.put_env(:arke_server, @config, Keyword.merge([enabled: true], opts))

  defp from(conn, ip), do: %{conn | remote_ip: ip}

  defp signin(conn), do: post(conn, "/lib/auth/signin", username: "nobody", password: "x")

  describe "auth rate limit (ARKE-AUTH-10)" do
    test "answers 429 past the limit, per client", %{conn: conn} do
      configure(limit: 3, window_ms: 60_000)
      ip = {10, 0, 0, 1}

      for _ <- 1..3, do: assert(signin(from(conn, ip)).status == 401)

      limited = signin(from(conn, ip))
      assert limited.status == 429
      assert [_seconds] = get_resp_header(limited, "retry-after")

      assert signin(from(conn, {10, 0, 0, 2})).status == 401
    end

    test "covers the other auth endpoints too", %{conn: conn} do
      configure(limit: 1, window_ms: 60_000)
      conn = from(conn, {10, 0, 0, 3})

      post(conn, "/lib/auth/recover_password", email: "nobody@arke.test")
      assert post(conn, "/lib/auth/refresh", refresh_token: "x").status == 429
    end

    test "reads the client from the configured proxy header", %{conn: conn} do
      configure(limit: 1, window_ms: 60_000, forwarded_header: "x-forwarded-for")
      proxy = {10, 0, 0, 4}

      via = fn client ->
        conn
        |> from(proxy)
        |> put_req_header("x-forwarded-for", "203.0.113.9, #{client}")
        |> signin()
      end

      assert via.("198.51.100.1").status == 401
      assert via.("198.51.100.1").status == 429
      assert via.("198.51.100.2").status == 401
    end

    test "can be disabled", %{conn: conn} do
      configure(enabled: false, limit: 1)
      conn = from(conn, {10, 0, 0, 5})

      for _ <- 1..3, do: assert(signin(conn).status == 401)
    end
  end
end
