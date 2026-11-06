defmodule ArkeServer.Plugs.PermissionTest do
  use ArkeServer.ConnCase, async: false
  use Mimic

  alias ArkeAuth.Utils.Permission

  setup :verify_on_exit!

  setup do
    user = get_user("permission_filter_user")
    stub(Permission, :get_public_permission, fn _arke, _project -> {:error, :none} end)
    %{user: user}
  end

  defp member_permission(filter) do
    stub(Permission, :get_member_permission, fn _member, _arke, _project ->
      {:ok, %{get: true, post: true, put: true, delete: true, filter: filter}}
    end)
  end

  describe "permission filter (ARKE-SRV-03)" do
    test "a filter that does not parse refuses the request", %{user: user} do
      member_permission("eq(owner,")

      build_authenticated_conn(user)
      |> get("/lib/arke_test_support/unit")
      |> json_response(403)
    end

    test "a permission without a filter still grants the request", %{user: user} do
      member_permission(nil)

      build_authenticated_conn(user)
      |> get("/lib/arke_test_support/unit")
      |> json_response(200)
    end

    test "an empty filter is read as no filter", %{user: user} do
      member_permission("")

      build_authenticated_conn(user)
      |> get("/lib/arke_test_support/unit")
      |> json_response(200)
    end
  end
end
