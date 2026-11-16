# Copyright 2023 Arkemis S.r.l.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule ArkeServer.Utils.LinkPermission do
  @moduledoc """
  Applies the caller's read permission to the units `load_links` expands.

  The Permission plug only checks the arke in the URL. Linked units can belong
  to any arke, so each of them is read through the same rules a
  `GET /lib/<arke>/unit` would apply: the public permission first, then the
  member's, with its filter and `child_only`. Arkes the caller may not read are
  not expanded.
  """

  alias ArkeAuth.Utils.Permission
  alias ArkeServer.Utils.QueryFilters

  @doc """
  Options to pass to `Arke.StructManager.encode/2` for a response to `conn`.
  """
  @spec encode_opts(Plug.Conn.t()) :: keyword()
  def encode_opts(conn), do: [link_query: link_query(conn)]

  @doc """
  The `:link_query` callback for `Arke.StructManager.encode/2`: given the query
  of the linked units of one arke, returns it with the caller's permission
  applied, or `:deny`.
  """
  @spec link_query(Plug.Conn.t()) :: (Arke.Core.Query.t(), atom() -> Arke.Core.Query.t() | :deny)
  def link_query(conn) do
    project = conn.assigns[:arke_project]
    member = ArkeAuth.Guardian.get_member(conn, impersonate: true)

    fn query, arke_id ->
      with {:ok, permission, member} <- read_permission(arke_id, project, member),
           {:ok, permission} <-
             ArkeServer.Plugs.Permission.get_permission_filter(conn, permission, member) do
        query
        |> QueryFilters.apply_query_filters(permission.filter)
        |> QueryFilters.apply_member_child_only(member, Map.get(permission, :child_only, false))
      else
        _ -> :deny
      end
    end
  end

  defp read_permission(arke_id, project, member) do
    arke_id = to_string(arke_id)

    case Permission.get_public_permission(arke_id, project) do
      {:ok, %{get: true} = permission} -> {:ok, permission, nil}
      _ -> member_permission(arke_id, project, member)
    end
  end

  defp member_permission(_arke_id, _project, nil), do: :deny

  defp member_permission(arke_id, project, member) do
    case Permission.get_member_permission(member, arke_id, project) do
      {:ok, %{get: true} = permission} -> {:ok, permission, member}
      _ -> :deny
    end
  end
end
