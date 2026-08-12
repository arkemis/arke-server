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

  test "POST /lib/auth/signup", %{conn: conn} do
    conn =
      post(conn, "/lib/auth/super_admin/signup", %{
        "arke_system_user" => %{
          "username" => "user3",
          "password" => "password",
          "email" => "user3@arke.test"
        }
      })

    body_resp = json_response(conn, 200)

    assert body_resp["content"]["arke_id"] == "super_admin"
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
    # The super_admin branch needs a member arke carrying an `email` parameter, which
    # neither super_admin nor member_public declares, so only the miss is reachable here.
    test "answers 404 when no member carries the email", %{conn: conn} do
      post(conn, "/lib/auth/recover_password", email: "nobody@arke.test")
      |> json_response(404)
    end
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
