defmodule ArkeServer.AuthOtpTest do
  @moduledoc """
  The `otp_mail` auth mode. AUTH_MODE and the review variables are read from
  the environment on every request, so the tests set them and run serially.
  """
  use ArkeServer.ConnCase, async: false

  alias ArkeServer.Support.AuthMember

  @env ["AUTH_MODE", "APP_REVIEW_EMAIL", "APP_REVIEW_CODE", "OTP_BYPASS_CODE"]

  setup do
    previous = Map.new(@env, &{&1, System.get_env(&1)})
    for var <- @env, do: System.delete_env(var)
    System.put_env("AUTH_MODE", "otp_mail")

    on_exit(fn ->
      for {var, value} <- previous,
          do: if(value, do: System.put_env(var, value), else: System.delete_env(var))
    end)

    :ok
  end

  defp signin(conn, username, otp),
    do: post(conn, "/lib/auth/signin", %{username: username, password: "password", otp: otp})

  describe "app review code (ARKE-AUTH-07)" do
    test "there is no default review code", %{conn: conn} do
      {user, _member} = AuthMember.create_user("reviewer_nocode")
      System.put_env("APP_REVIEW_EMAIL", user.data.username)

      assert signin(conn, "reviewer_nocode", "1234").status == 401
    end

    test "with no review code a reviewer gets a real OTP", %{conn: conn} do
      {user, member} = AuthMember.create_user("reviewer_realotp")
      System.put_env("APP_REVIEW_EMAIL", user.data.username)

      assert signin(conn, "reviewer_realotp", nil).status == 200
      assert ArkeAuth.Boundary.OtpManager.get_code(:test_schema, member, "signin")
    end

    test "the configured review code signs the reviewer in", %{conn: conn} do
      {user, _member} = AuthMember.create_user("reviewer_code")
      System.put_env("APP_REVIEW_EMAIL", "someone_else, #{user.data.username}")
      System.put_env("APP_REVIEW_CODE", "246810")

      body = signin(conn, "reviewer_code", "246810") |> json_response(200)
      assert body["content"]["access_token"]
    end

    test "wrong review codes are throttled", %{conn: conn} do
      {user, _member} = AuthMember.create_user("reviewer_brute")
      System.put_env("APP_REVIEW_EMAIL", user.data.username)
      System.put_env("APP_REVIEW_CODE", "246810")

      on_exit(fn ->
        ArkeAuth.Boundary.AttemptLimiter.reset({:app_review_code, "reviewer_brute"})
      end)

      for _ <- 1..4, do: assert(signin(conn, "reviewer_brute", "000000").status == 401)

      assert signin(conn, "reviewer_brute", "000000").status == 429
      assert signin(conn, "reviewer_brute", "246810").status == 429
    end
  end

  describe "super_admin and the second factor (ARKE-AUTH-09)" do
    test "a super_admin password sign-in asks for an OTP", %{conn: conn} do
      user = get_user("admin_2fa")
      member = get_member(user)
      assert member.arke_id == :super_admin

      body = signin(conn, "admin_2fa", nil) |> json_response(200)

      refute body["content"]["access_token"]
      assert ArkeAuth.Boundary.OtpManager.get_code(:test_schema, member, "signin")
    end

    test "a super_admin password without the OTP gets no tokens", %{conn: conn} do
      get_user("admin_2fa_wrong")

      conn = signin(conn, "admin_2fa_wrong", "000000")

      assert conn.status == 401
      refute conn.resp_body =~ "access_token"
    end
  end

  describe "OTP verification (ARKE-AUTH-08)" do
    alias ArkeAuth.Core.Otp

    defp wrong(code),
      do: code |> String.to_integer() |> Kernel.+(1) |> rem(1_000_000) |> to_string()

    test "the signin code verifies once", %{conn: conn} do
      {_user, member} = AuthMember.create_user("otp_signin")
      {:ok, otp} = Otp.generate(:test_schema, member.id, "signin")

      assert signin(conn, "otp_signin", otp.data.code) |> json_response(200)
      assert signin(conn, "otp_signin", otp.data.code).status == 401
    end

    test "a numeric JSON code is accepted", %{conn: conn} do
      {_user, member} = AuthMember.create_user("otp_signin_int")
      {:ok, otp} = Otp.generate(:test_schema, member.id, "signin")
      {:ok, _} = QueryManager.update(otp, code: "042817")

      assert signin(conn, "otp_signin_int", 42817).status == 200
    end

    test "the signin code is burnt after five wrong guesses", %{conn: conn} do
      {_user, member} = AuthMember.create_user("otp_signin_brute")
      {:ok, otp} = Otp.generate(:test_schema, member.id, "signin")

      for _ <- 1..4,
          do: assert(signin(conn, "otp_signin_brute", wrong(otp.data.code)).status == 401)

      assert signin(conn, "otp_signin_brute", wrong(otp.data.code)).status == 429
      assert signin(conn, "otp_signin_brute", otp.data.code).status == 401
    end

    test "an expired signin code answers 410", %{conn: conn} do
      {_user, member} = AuthMember.create_user("otp_signin_expired")
      past = NaiveDateTime.utc_now() |> NaiveDateTime.add(-1, :second)
      {:ok, otp} = Otp.generate(:test_schema, member.id, "signin", past)

      assert signin(conn, "otp_signin_expired", otp.data.code).status == 410
    end

    test "the reset password code is checked the same way", %{conn: conn} do
      {user, member} = AuthMember.create_user("otp_reset")
      {:ok, otp} = Otp.generate(:test_schema, member.id, "reset_password")

      reset = fn code ->
        post(conn, "/lib/auth/reset_password", %{
          email: user.data.email,
          otp: code,
          new_password: "changed_password"
        })
      end

      for _ <- 1..4, do: assert(reset.(wrong(otp.data.code)).status == 401)
      assert reset.(wrong(otp.data.code)).status == 429
      assert reset.(otp.data.code).status == 401

      {:ok, otp} = Otp.generate(:test_schema, member.id, "reset_password")
      assert reset.(otp.data.code).status == 200

      assert {:ok, _, _, _} =
               ArkeAuth.Core.Auth.validate_credentials(
                 "otp_reset",
                 "changed_password",
                 :test_schema
               )
    end

    test "the signup code is checked the same way", %{conn: conn} do
      AuthMember.ensure_arke(["arke_auth_member", "self_signup"])
      username = "otp_signup@arke.test"
      {:ok, otp} = Otp.generate(:test_schema, username, "signup")

      signup = fn code ->
        post(conn, "/lib/auth/#{AuthMember.arke_id()}/signup", %{
          otp: code,
          email: username,
          first_name: "Otp",
          last_name: "Signup",
          arke_system_user: %{username: username, password: "password", email: username}
        })
      end

      for _ <- 1..4, do: assert(signup.(wrong(otp.data.code)).status == 401)
      assert signup.(wrong(otp.data.code)).status == 429
      assert signup.(otp.data.code).status == 401

      {:ok, otp} = Otp.generate(:test_schema, username, "signup")
      assert signup.(otp.data.code) |> json_response(200)
    end
  end

  describe "unknown emails (no account enumeration)" do
    test "recover_password answers as for a known email", %{conn: conn} do
      {user, _member} = AuthMember.create_user("recover_known")

      known = post(conn, "/lib/auth/recover_password", %{email: user.data.email, otp: nil})
      unknown = post(conn, "/lib/auth/recover_password", %{email: "nobody@arke.test", otp: nil})

      assert known.status == 200
      assert unknown.status == known.status
      assert unknown.resp_body == known.resp_body
    end

    test "reset_password answers 401 instead of crashing", %{conn: conn} do
      post(conn, "/lib/auth/reset_password", %{
        email: "nobody@arke.test",
        otp: "123456",
        new_password: "whatever"
      })
      |> json_response(401)
    end
  end
end
