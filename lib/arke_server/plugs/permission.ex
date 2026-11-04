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
defmodule ArkeServer.Plugs.Permission do
  import Plug.Conn
  alias ArkeAuth.Utils.Permission
  alias Arke.Utils.ErrorGenerator, as: Error
  alias ArkeServer.Utils.QueryFilters

  def init(default), do: default

  def call(%Plug.Conn{request_path: "/lib/auth/change_password"} = conn, _default) do
    get_auth_conn(conn)
  end

  def call(%Plug.Conn{path_params: %{"arke_id" => arke_id}} = conn, _default) do
    check_permission(conn, arke_id)
  end

  def call(%Plug.Conn{path_params: %{"group_id" => group_id}} = conn, _default) do
    check_permission(conn, group_id)
  end

  def call(%Plug.Conn{path_params: %{"parameter_id" => parameter_id}} = conn, _default) do
    # check_permission(conn,parameter_id)
    conn
  end

  # handle arke_project and unit global search
  def call(%Plug.Conn{method: method, request_path: req_path} = conn, default) do
    regex = ~r{/lib/([^/]+)}
    arke_id = Regex.run(regex, req_path) |> List.last()

    if is_nil(arke_id) do
      conn
    else
      new_conn =
        if arke_id == "arke_project", do: assign(conn, :arke_project, "arke_system"), else: conn

      check_permission(new_conn, arke_id)
    end
  end

  def call(conn, default), do: conn

  defp check_permission(%Plug.Conn{method: method} = conn, arke_id) do
    # todo: caipre cosa fare se arke_project non c'è,
    project = conn.assigns[:arke_project]
    action = parse_method(method)

    with {:ok, data} <- Permission.get_public_permission(arke_id, project),
         true <- is_permitted?(data, action) do
      assign_permission_filter(conn, data, nil)
    else
      _ ->
        auth_conn = get_auth_conn(conn)

        with %Plug.Conn{halted: false} <- auth_conn,
             {:ok, data} <-
               Permission.get_member_permission(
                 ArkeAuth.Guardian.get_member(auth_conn, impersonate: true),
                 arke_id,
                 project
               ),
             true <- is_permitted?(data, action) do
          assign_permission_filter(
            auth_conn,
            data,
            ArkeAuth.Guardian.get_member(auth_conn, impersonate: true)
          )
        else
          %Plug.Conn{halted: true} = auth_conn ->
            auth_conn

          _ ->
            member = ArkeAuth.Guardian.get_member(auth_conn, impersonate: true) || %{data: %{}}

            case Map.get(member.data, :subscription_active) do
              false -> halt_conn(conn, "payment required", 402)
              _ -> halt_conn(conn, "forbidden", 403)
            end
        end
    end
  end

  # Without enable_impersonate the permissions are those of the bearer token,
  # which only AuthPipeline binds to the requested project, so the
  # impersonate-token header is then ignored.
  defp get_auth_conn(conn) do
    case {impersonate_enabled?(), get_impersonate_header(conn)} do
      {true, {:ok, [header | _]}} when header != "" ->
        ArkeServer.Plugs.ImpersonateAuthPipeline.call(conn, [])

      _ ->
        ArkeServer.Plugs.AuthPipeline.call(conn, [])
    end
  end

  defp impersonate_enabled?() do
    Application.get_env(:arke_auth, ArkeAuth.Guardian, [])
    |> Keyword.get(:enable_impersonate, false)
  end

  defp halt_conn(conn, message, status) do
    {:error, msg} = Error.create(:auth, message)

    ArkeServer.ResponseManager.send_resp(conn, status, nil, msg)
    |> Plug.Conn.halt()
  end

  defp is_permitted?(_permission, nil), do: false
  defp is_permitted?(permission, action), do: Map.get(permission, action, false)

  # Any method string reaches the plug; only these map to a permission.
  defp parse_method("GET"), do: :get
  defp parse_method("POST"), do: :post
  defp parse_method("PUT"), do: :put
  defp parse_method("PATCH"), do: :put
  defp parse_method("DELETE"), do: :delete
  defp parse_method(_method), do: nil

  # A nil filter on the permission means it grants every row. A filter that
  # cannot be parsed must not be read the same way: the request is refused.
  defp assign_permission_filter(conn, permission, member) do
    case get_permission_filter(conn, permission, member) do
      {:ok, permission} -> assign(conn, :permission_filter, permission)
      :error -> halt_conn(conn, "forbidden", 403)
    end
  end

  defp get_permission_filter(_conn, %{filter: filter} = permission, _member)
       when filter in [nil, ""],
       do: {:ok, Map.put(permission, :filter, nil)}

  defp get_permission_filter(conn, permission, member) do
    filter = get_member_filter(permission.filter, member)

    case QueryFilters.get_from_string(conn, filter) do
      {:ok, data} -> {:ok, Map.put(permission, :filter, data)}
      {:error, _msg} -> :error
    end
  end

  defp get_member_filter(filter, member) when is_binary(filter) and not is_nil(member),
    do: String.replace(filter, "{{arke_member}}", to_string(member.id))

  defp get_member_filter(filter, _member), do: filter

  defp get_impersonate_header(conn) do
    header = get_req_header(conn, "impersonate-token")
    {:ok, header}
  end
end
