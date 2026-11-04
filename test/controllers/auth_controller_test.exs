defmodule ArkeServer.AuthControllerTest do
  use ArkeServer.ConnCase

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

    test "signs up as a member arke in the self_signup group", %{conn: conn} do
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

    test "refuses a member arke outside self_signup", %{conn: conn} do
      refute ArkeServer.Utils.MemberArke.self_signup?("member_public", :test_schema)

      signup(conn, "member_public", "not_open") |> json_response(403)
    end

    test "refuses an unknown arke", %{conn: conn} do
      signup(conn, "no_such_member_arke", "nobody") |> json_response(403)
    end

    test "super_admin stays refused in a project that lists it" do
      Arke.LinkManager.add_node(:test_schema, "self_signup", "super_admin", "group")
      Arke.LinkManager.add_node(:test_schema, "enable_sso", "super_admin", "group")

      refute ArkeServer.Utils.MemberArke.self_signup?("super_admin", :test_schema)
      refute ArkeServer.Utils.MemberArke.sso_signup?("super_admin", :test_schema)
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

  describe "POST /lib/auth/signin with an auth_token" do
    test "signs in when the token points at a live member", %{conn: conn} do
      user = get_user("user_authtoken")
      member = get_member(user)

      {:ok, token} =
        ArkeAuth.Core.TemporaryToken.generate_auth_token(
          :test_schema,
          member,
          %{days: 1},
          true,
          []
        )

      body = post(conn, "/lib/auth/signin", auth_token: to_string(token.id)) |> json_response(200)

      assert body["content"]["access_token"]
      delete_user("user_authtoken")
    end

    test "answers 403 when the token points at a member that no longer exists", %{conn: conn} do
      user = get_user("user_authtoken_gone")
      member = get_member(user)

      {:ok, token} =
        ArkeAuth.Core.TemporaryToken.generate_auth_token(
          :test_schema,
          member,
          %{days: 1},
          true,
          []
        )

      {:ok, nil} = QueryManager.delete(:test_schema, member)

      body = post(conn, "/lib/auth/signin", auth_token: to_string(token.id)) |> json_response(403)

      assert List.first(body["content"])["message"] == "member not found"
    end

    test "signs only the member's public fields into the token", %{conn: conn} do
      user = get_user("user_authtoken_claims")
      member = get_member(user)

      {:ok, token} =
        ArkeAuth.Core.TemporaryToken.generate_auth_token(:test_schema, member, 1, true, [])

      body = post(conn, "/lib/auth/signin", auth_token: to_string(token.id)) |> json_response(200)
      {:ok, claims} = Guardian.decode_and_verify(body["content"]["access_token"])

      assert claims["sub"]["id"] == to_string(member.id)
      assert claims["sub"]["project"] == "test_schema"

      assert Map.keys(claims["sub"]) --
               ~w(id project email first_name last_name subscription_active) == []

      delete_user("user_authtoken_claims")
    end

    test "answers 401 for an expired auth_token", %{conn: conn} do
      user = get_user("user_authtoken_expired")
      member = get_member(user)

      {:ok, token} =
        ArkeAuth.Core.TemporaryToken.generate_auth_token(:test_schema, member, 1, true, [])

      {:ok, _} =
        QueryManager.update(token,
          expiration_datetime: NaiveDateTime.utc_now() |> NaiveDateTime.add(-1, :second)
        )

      post(conn, "/lib/auth/signin", auth_token: to_string(token.id)) |> json_response(401)
      delete_user("user_authtoken_expired")
    end

    test "answers 401 for an auth_token without an expiry", %{conn: conn} do
      user = get_user("user_authtoken_noexpiry")
      member = get_member(user)

      {:ok, token} =
        ArkeAuth.Core.TemporaryToken.generate_auth_token(:test_schema, member, 1, true, [])

      {:ok, _} = QueryManager.update(token, expiration_datetime: nil)

      post(conn, "/lib/auth/signin", auth_token: to_string(token.id)) |> json_response(401)
      delete_user("user_authtoken_noexpiry")
    end

    test "answers 401 for an unknown auth_token", %{conn: conn} do
      post(conn, "/lib/auth/signin", auth_token: "no_such_token") |> json_response(401)
    end
  end

  describe "POST /lib/auth/reset_password" do
    test "updates the password and consumes the token", %{conn: conn} do
      user = get_user("user_reset")

      token_model = ArkeManager.get(:reset_password_token, :arke_system)

      {:ok, token_unit} =
        QueryManager.create(:arke_system, token_model, user_id: to_string(user.id))

      post(conn, "/lib/auth/reset_password",
        token: token_unit.data.token,
        new_password: "changed_password"
      )
      |> json_response(200)

      assert QueryManager.get_by(
               project: :arke_system,
               arke_id: :reset_password_token,
               token: token_unit.data.token
             ) == nil

      post(conn, "/lib/auth/signin", username: "user_reset", password: "changed_password")
      |> json_response(200)

      delete_user("user_reset")
    end

    test "answers 400 for an unknown token", %{conn: conn} do
      post(conn, "/lib/auth/reset_password", token: "no_such_token", new_password: "whatever")
      |> json_response(400)
    end
  end

  describe "POST /lib/auth/recover_password" do
    test "answers 200 when no member carries the email", %{conn: conn} do
      body = post(conn, "/lib/auth/recover_password", email: "nobody@arke.test")

      assert body.status == 200
      assert body.resp_body =~ "An email has been sent"
    end
  end

  describe "POST /lib/auth/reset_password without the required params" do
    test "answers 400 instead of crashing", %{conn: conn} do
      post(conn, "/lib/auth/reset_password", new_password: "whatever") |> json_response(400)
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

  describe "auth error handler" do
    test "reports the guardian error type when an authorization header is present" do
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer whatever")

      assert %Plug.Conn{status: 401} =
               ArkeServer.ErrorHandlers.Auth.auth_error(conn, {:invalid_token, :reason}, [])
    end

    test "reports the missing header instead when there is none" do
      assert %Plug.Conn{status: 401} =
               ArkeServer.ErrorHandlers.Auth.auth_error(build_conn(), {:unauthenticated, :r}, [])
    end
  end
end
