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
end
