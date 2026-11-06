defmodule ArkeServer.ApiDocsTest do
  use ArkeServer.ConnCase, async: false

  alias ArkeServer.Support.AuthMember

  describe "/lib/doc (ARKE-SRV-06)" do
    test "needs a token", %{conn: conn} do
      get(conn, "/lib/doc/openapi") |> json_response(401)
      get(conn, "/lib/doc/swaggerui") |> json_response(401)
    end

    test "needs the project header" do
      build_conn() |> get("/lib/doc/openapi") |> json_response(401)
    end

    test "is refused to members that are not super_admin" do
      {user, _member} = AuthMember.create_user("docs_reader")

      build_authenticated_conn(user)
      |> get("/lib/doc/openapi")
      |> json_response(403)
    end

    test "is served to a super_admin" do
      body = build_authenticated_conn(get_user("docs_admin")) |> get("/lib/doc/openapi")

      assert json_response(body, 200)["openapi"]
    end

    test "can be opened up for local development", %{conn: conn} do
      Application.put_env(:arke_server, :public_api_docs, true)
      on_exit(fn -> Application.delete_env(:arke_server, :public_api_docs) end)

      assert get(conn, "/lib/doc/openapi") |> json_response(200)
    end
  end
end
