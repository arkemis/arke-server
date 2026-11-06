defmodule ArkeServer.AtomInputTest do
  @moduledoc """
  Request input must not create atoms (ARKE-SRV-04): the atom table is never
  garbage collected, so a client could otherwise exhaust it and crash the node.
  """
  use ArkeServer.ConnCase, async: false
  use Mimic

  alias ArkeAuth.Utils.Permission

  setup :verify_on_exit!

  setup do
    user = get_user("atom_input_user")
    stub(Permission, :get_public_permission, fn _arke, _project -> {:error, :none} end)

    stub(Permission, :get_member_permission, fn _member, _arke, _project ->
      {:ok, %{get: true, post: true, put: true, delete: true, filter: nil}}
    end)

    %{conn: build_authenticated_conn(user)}
  end

  defp fresh_name(), do: "never_an_atom_" <> Base.encode16(:crypto.strong_rand_bytes(8))

  defp refute_atom(name) do
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "an unknown arke function name", %{conn: conn} do
    name = fresh_name()

    conn |> get("/lib/arke_test_support/function/#{name}") |> json_response(404)
    refute_atom(name)
  end

  test "an unknown group function name", %{conn: conn} do
    name = fresh_name()

    conn |> get("/lib/group/arke_auth_member/function/#{name}") |> json_response(404)
    refute_atom(name)
  end

  test "an unknown arke on create and struct", %{conn: conn} do
    name = fresh_name()

    post(conn, "/lib/#{name}/unit", %{}) |> response(404)
    get(conn, "/lib/#{name}/struct") |> json_response(404)
    refute_atom(name)
  end
end
