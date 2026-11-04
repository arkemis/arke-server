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
      post(conn, "/lib/auth/signup", username: "user3", password: "password", type: "customer")

    body_resp = json_response(conn, 201)
    assert body_resp["content"]["username"] == "user3"

    delete_user("user2")
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

    conn = post(conn, "/lib/auth/refresh")
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
        |> Plug.Conn.put_req_header("authorization", "Bearer INVALID TOKEN")
        |> post("/lib/auth/verify")
        |> json_response(401)

      assert List.first(conn["messages"])["message"] == "invalid_token"
      delete_user("user2")
    end

    test "error missing auth header" do
      conn =
        build_conn()
        |> post("/lib/auth/verify")
        |> json_response(401)

      assert List.first(conn["messages"])["message"] == "missing authorization header"
      delete_user("user2")
    end
  end
end
