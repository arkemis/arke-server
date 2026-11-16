defmodule ArkeServer.AuthControllerTest do
  use ArkeServer.ConnCase
  use Mimic

  def create_user_setup(context) do
    get_user("user2")
    context
  end

  describe "POST /lib/auth/signin" do
    setup [:create_user_setup]

    test "success", %{conn: conn} do
      conn = post(conn, "/lib/auth/signin", username: "user2", password: "password")
      assert conn.status == 200
      delete_user("user2")
    end

    test "error", %{conn: conn} do
      conn = post(conn, "/lib/auth/signin", username: "user2")
      assert conn.status == 404
      delete_user("user2")
    end
  end

  describe "POST /lib/auth/:arke_id/signup (ARKE-AUTH-01)" do
    alias ArkeServer.Support.AuthMember

    defp put_self_signup_arkes(arkes) do
      previous = Application.get_env(:arke_server, :self_signup_arkes)
      on_exit(fn -> Application.put_env(:arke_server, :self_signup_arkes, previous) end)

      if arkes,
        do: Application.put_env(:arke_server, :self_signup_arkes, arkes),
        else: Application.delete_env(:arke_server, :self_signup_arkes)
    end

    defp signup(conn, arke_id, username) do
      post(conn, "/lib/auth/#{arke_id}/signup", %{
        "email" => "#{username}@arke.test",
        "arke_system_user" => %{
          "username" => username,
          "password" => "password",
          "email" => "#{username}@arke.test"
        }
      })
    end

    test "signs up as a member arke in the self-signup list", %{conn: conn} do
      body_resp = signup(conn, AuthMember.arke_id(), "user3") |> json_response(200)

      assert body_resp["content"]["arke_id"] == to_string(AuthMember.arke_id())
      assert is_binary(body_resp["content"]["access_token"])
      assert is_binary(body_resp["content"]["refresh_token"])

      user =
        QueryManager.get_by(
          project: :arke_system,
          arke_id: :user,
          id: body_resp["content"]["arke_system_user"]
        )

      assert user.data.username == "user3"

      delete_user("user3")
    end

    test "ignores the fields a client must not set", %{conn: conn} do
      body =
        post(conn, "/lib/auth/#{AuthMember.arke_id()}/signup", %{
          "email" => "picky@arke.test",
          "inactive" => true,
          "id" => "chosen_member_id",
          "arke_system_user" => %{
            "username" => "picky",
            "password" => "password",
            "email" => "picky@arke.test"
          }
        })
        |> json_response(200)

      refute body["content"]["id"] == "chosen_member_id"
      member = QueryManager.get_by(project: :test_schema, id: body["content"]["id"])
      refute member.data.inactive

      delete_user("picky")
    end

    test "refuses super_admin", %{conn: conn} do
      body = signup(conn, "super_admin", "would_be_admin") |> json_response(403)

      assert List.first(body["messages"])["message"] == "signup not allowed"
      assert QueryManager.get_by(project: :arke_system, username: "would_be_admin") == nil
    end

    test "refuses a member arke outside the self-signup list", %{conn: conn} do
      refute ArkeServer.Utils.MemberArke.self_signup?("member_public", :test_schema)

      signup(conn, "member_public", "not_open") |> json_response(403)
    end

    test "refuses an unknown arke", %{conn: conn} do
      signup(conn, "no_such_member_arke", "nobody") |> json_response(403)
    end

    test "super_admin stays refused when it is listed" do
      put_self_signup_arkes([:test_auth_member, "super_admin"])
      Arke.LinkManager.add_node(:test_schema, "enable_sso", "super_admin", "group")

      refute ArkeServer.Utils.MemberArke.self_signup?("super_admin", :test_schema)
      refute ArkeServer.Utils.MemberArke.sso_signup?("super_admin", :test_schema)
    end

    test "a listed arke must also be an arke_auth_member of the project", %{conn: conn} do
      put_self_signup_arkes([:test_auth_member, :member_public, :arke])

      assert ArkeServer.Utils.MemberArke.self_signup?("member_public", :test_schema)
      refute ArkeServer.Utils.MemberArke.self_signup?("arke", :test_schema)
      signup(conn, "arke", "not_a_member") |> json_response(403)
    end

    test "sign-up is closed when nothing is listed", %{conn: conn} do
      put_self_signup_arkes(nil)

      refute ArkeServer.Utils.MemberArke.self_signup?(AuthMember.arke_id(), :test_schema)
      signup(conn, AuthMember.arke_id(), "closed") |> json_response(403)
    end
  end

  test "POST /lib/auth/refresh", %{conn: conn} do
    create_user_setup(nil)
    # Get tokens
    get_token_conn = post(conn, "/lib/auth/signin", username: "user2", password: "password")
    signin_body_resp = json_response(get_token_conn, 200)
    old_access_token = signin_body_resp["content"]["access_token"]
    old_refresh_token = signin_body_resp["content"]["refresh_token"]

    conn =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{old_refresh_token}")
      |> Plug.Conn.put_req_header("arke-project-key", "test_schema")

    conn = post(conn, "/lib/auth/refresh", refresh_token: old_refresh_token)
    body_resp = json_response(conn, 200)
    new_access_token = body_resp["content"]["access_token"]
    new_refresh_token = body_resp["content"]["refresh_token"]

    assert new_access_token != old_access_token and new_refresh_token != old_refresh_token
    delete_user("user2")
  end

  describe "token types (ARKE-AUTH-04)" do
    setup [:create_user_setup]

    defp tokens(conn) do
      post(conn, "/lib/auth/signin", username: "user2", password: "password")
      |> json_response(200)
      |> Map.fetch!("content")
    end

    test "a refresh token is not a bearer token", %{conn: conn} do
      %{"refresh_token" => refresh_token} = tokens(conn)

      build_conn()
      |> Plug.Conn.put_req_header("arke-project-key", "test_schema")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{refresh_token}")
      |> post("/lib/auth/verify")
      |> json_response(401)
    end

    test "refresh needs no authorization header", %{conn: conn} do
      %{"refresh_token" => refresh_token} = tokens(conn)

      body = post(conn, "/lib/auth/refresh", refresh_token: refresh_token) |> json_response(200)
      assert body["content"]["access_token"]
    end

    test "an access token cannot be exchanged for new tokens", %{conn: conn} do
      %{"access_token" => access_token} = tokens(conn)

      build_conn()
      |> Plug.Conn.put_req_header("arke-project-key", "test_schema")
      |> Plug.Conn.put_req_header("authorization", "Bearer #{access_token}")
      |> post("/lib/auth/refresh", refresh_token: access_token)
      |> json_response(400)
    end
  end

  describe "token project (ARKE-SRV-01)" do
    setup [:create_user_setup]

    test "a token is rejected for another project than its own" do
      user = Arke.QueryManager.get_by(project: :arke_system, username: "user2")

      body =
        build_authenticated_conn(user)
        |> Plug.Conn.put_req_header("arke-project-key", "arke_system")
        |> post("/lib/auth/verify")
        |> json_response(401)

      assert List.first(body["messages"])["message"] == "invalid_project"
    end

    test "a project member cannot manage projects" do
      user = Arke.QueryManager.get_by(project: :arke_system, username: "user2")

      build_authenticated_conn(user)
      |> get("/lib/arke_project/unit")
      |> json_response(401)
    end

    test "the impersonate-token header is ignored while impersonation is off" do
      user = Arke.QueryManager.get_by(project: :arke_system, username: "user2")
      {:ok, token, _} = Guardian.encode_and_sign(get_member(user))

      build_system_conn(user)
      |> Plug.Conn.put_req_header("arke-project-key", "test_schema")
      |> Plug.Conn.put_req_header("impersonate-token", "Bearer #{token}")
      |> post("/lib/auth/verify")
      |> json_response(401)
    end
  end

  describe "POST /lib/auth/verify" do
    setup [:create_user_setup]

    test "success" do
      user = Arke.QueryManager.get_by(project: :arke_system, username: "user2")

      conn =
        build_authenticated_conn(user)
        |> post("/lib/auth/verify")

      assert conn.status == 200
      delete_user("user2")
    end

    test "error invalid token" do
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("arke-project-key", "test_schema")
        |> Plug.Conn.put_req_header("authorization", "Bearer INVALID TOKEN")
        |> post("/lib/auth/verify")
        |> json_response(401)

      assert List.first(conn["messages"])["message"] == "invalid_token"
      delete_user("user2")
    end

    test "error missing auth header" do
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("arke-project-key", "test_schema")
        |> post("/lib/auth/verify")
        |> json_response(401)

      assert List.first(conn["messages"])["message"] == "missing authorization header"
      delete_user("user2")
    end
  end

  describe "POST /lib/auth/signin with an auth_token (ARKE-AUTH-06)" do
    alias ArkeAuth.Core.TemporaryToken

    test "answers 401 for an expired auth_token", %{conn: conn} do
      member = get_member(get_user("user_authtoken_expired"))
      {:ok, token} = TemporaryToken.generate_auth_token(:test_schema, member, 1, true, [])
      Process.sleep(1_100)

      post(conn, "/lib/auth/signin", auth_token: token.id) |> json_response(401)
      delete_user("user_authtoken_expired")
    end

    test "a single-use auth_token signs in once", %{conn: conn} do
      member = get_member(get_user("user_authtoken_once"))
      {:ok, token} = TemporaryToken.generate_auth_token(:test_schema, member)

      post(conn, "/lib/auth/signin", auth_token: token.id) |> json_response(200)
      post(conn, "/lib/auth/signin", auth_token: token.id) |> json_response(401)
      delete_user("user_authtoken_once")
    end

    test "answers 403 when the token points at no member", %{conn: conn} do
      {:ok, token} = TemporaryToken.generate_auth_token(:test_schema, "no_such_member")

      post(conn, "/lib/auth/signin", auth_token: token.id) |> json_response(403)
    end

    test "answers 401 for an unknown auth_token", %{conn: conn} do
      post(conn, "/lib/auth/signin", auth_token: "no_such_token") |> json_response(401)
    end

    # Projects seeded before this change still have the temporary_token arke,
    # so the endpoint may answer; it must not list any token.
    test "tokens are not reachable through the unit endpoints" do
      member = get_member(get_user("user_authtoken_hidden"))
      {:ok, token} = TemporaryToken.generate_auth_token(:test_schema, member)

      conn = build_authenticated_conn() |> get("/lib/temporary_token/unit")

      refute conn.resp_body =~ token.id
      if conn.status == 200, do: assert(json_response(conn, 200)["content"]["count"] == 0)
      delete_user("user_authtoken_hidden")
    end
  end

  describe "POST /lib/auth/signin with a member token" do
    alias ArkeAuth.Core.MemberToken

    test "signs in once", %{conn: conn} do
      member = get_member(get_user("user_member_token"))
      {:ok, token} = MemberToken.issue(:test_schema, member.id)

      body = post(conn, "/lib/auth/signin", token: token) |> json_response(200)
      assert body["content"]["access_token"]

      post(conn, "/lib/auth/signin", token: token) |> json_response(401)
      delete_user("user_member_token")
    end

    test "answers 401 for an expired token", %{conn: conn} do
      member = get_member(get_user("user_member_token_expired"))
      {:ok, token} = MemberToken.issue(:test_schema, member.id, 1)
      Process.sleep(1_100)

      post(conn, "/lib/auth/signin", token: token) |> json_response(401)
      delete_user("user_member_token_expired")
    end

    # AuthMember's arke has the `inactive` parameter; super_admin's does not.
    test "answers 401 for an inactive member", %{conn: conn} do
      {_user, member} = ArkeServer.Support.AuthMember.create_user("user_member_token_inactive")
      {:ok, member} = QueryManager.update(member, inactive: true)
      assert member.data.inactive
      {:ok, token} = MemberToken.issue(:test_schema, member.id)

      post(conn, "/lib/auth/signin", token: token) |> json_response(401)
    end

    test "a value in the legacy auth_token field does not sign in", %{conn: conn} do
      member = get_member(get_user("user_member_token_legacy"))
      QueryManager.update(member, auth_token: "legacy_token_value")

      post(conn, "/lib/auth/signin", token: "legacy_token_value") |> json_response(401)
      delete_user("user_member_token_legacy")
    end
  end

  test "credentials are filtered out of the request logs (ARKE-AUTH-06)" do
    filtered =
      Phoenix.Logger.filter_values(%{
        "auth_token" => "a",
        "refresh_token" => "b",
        "otp" => "c",
        "new_password" => "d",
        "username" => "e"
      })

    assert filtered == %{
             "auth_token" => "[FILTERED]",
             "refresh_token" => "[FILTERED]",
             "otp" => "[FILTERED]",
             "new_password" => "[FILTERED]",
             "username" => "e"
           }
  end

  describe "POST /lib/auth/recover_password" do
    test "answers 200 when no member carries the email", %{conn: conn} do
      body = post(conn, "/lib/auth/recover_password", email: "nobody@arke.test")

      assert body.status == 200
      assert body.resp_body =~ "An email has been sent"
    end
  end

  describe "password reset link (default mode)" do
    alias ArkeServer.Support.AuthMember

    defp request_reset_token(conn, email) do
      test_pid = self()

      Mimic.expect(ArkeServer.TestMailer, :reset_password, fn _conn, _user, opts ->
        send(test_pid, {:reset_endpoint, Keyword.fetch!(opts, :endpoint)})
        {:ok, opts}
      end)

      post(conn, "/lib/auth/recover_password", email: email) |> json_response(200)
      assert_received {:reset_endpoint, endpoint}
      endpoint |> String.split("/") |> List.last()
    end

    defp reset(conn, token, password),
      do: post(conn, "/lib/auth/reset_password", token: token, new_password: password)

    test "the mailed token resets the password once", %{conn: conn} do
      {user, _member} = AuthMember.create_user("reset_link")
      token = request_reset_token(conn, user.data.email)

      assert reset(conn, token, "brand_new_password").status == 200

      assert {:ok, _, _, _} =
               ArkeAuth.Core.Auth.validate_credentials(
                 "reset_link",
                 "brand_new_password",
                 :test_schema
               )

      assert reset(conn, token, "another_password").status == 400
    end

    test "a tampered token answers 400", %{conn: conn} do
      {user, _member} = AuthMember.create_user("reset_link_tampered")
      token = request_reset_token(conn, user.data.email)

      assert reset(conn, token <> "x", "brand_new_password").status == 400
      assert reset(conn, "not.a-token", "brand_new_password").status == 400
    end

    test "an unknown email gets the same answer as a known one", %{conn: conn} do
      {user, _member} = AuthMember.create_user("reset_link_known")
      Mimic.stub(ArkeServer.TestMailer, :reset_password, fn _conn, _user, opts -> {:ok, opts} end)

      known = post(conn, "/lib/auth/recover_password", email: user.data.email)
      unknown = post(conn, "/lib/auth/recover_password", email: "nobody_reset@arke.test")

      assert known.status == unknown.status
      assert known.resp_body == unknown.resp_body
    end
  end

  describe "POST /lib/auth/reset_password without the required params" do
    test "answers 400 instead of crashing", %{conn: conn} do
      post(conn, "/lib/auth/reset_password", new_password: "whatever") |> json_response(400)
    end
  end

  describe "POST /lib/auth/signin with an auth_token, token claims" do
    test "signs only the member's public fields into the token", %{conn: conn} do
      user = get_user("user_authtoken_claims")
      member = get_member(user)

      {:ok, token} =
        ArkeAuth.Core.TemporaryToken.generate_auth_token(:test_schema, member, 1, true, [])

      body = post(conn, "/lib/auth/signin", auth_token: token.id) |> json_response(200)
      {:ok, claims} = Guardian.decode_and_verify(body["content"]["access_token"])

      assert claims["sub"]["id"] == to_string(member.id)
      assert claims["sub"]["project"] == "test_schema"

      assert Map.keys(claims["sub"]) --
               ~w(id project email first_name last_name subscription_active) == []

      delete_user("user_authtoken_claims")
    end
  end
end
