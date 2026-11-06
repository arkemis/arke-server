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

defmodule ArkeServer.Plugs.ApiDocsAuth do
  @moduledoc """
  Restricts the OpenAPI spec and Swagger UI under `/lib/doc` to super_admin
  members: the spec maps every endpoint and payload of the deployment.

  The request needs the `arke-project-key` header and a super_admin access
  token of that project. Swagger UI cannot send them while loading the spec,
  so for local development the docs can be opened up with
  `config :arke_server, :public_api_docs, true`.
  """
  alias Arke.Utils.ErrorGenerator, as: Error

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    if Application.get_env(:arke_server, :public_api_docs, false),
      do: conn,
      else: authorize(conn)
  end

  defp authorize(conn) do
    with %Plug.Conn{halted: false} = conn <- ArkeServer.Plugs.GetProject.call(conn, []),
         %Plug.Conn{halted: false} = conn <- ArkeServer.Plugs.AuthPipeline.call(conn, []) do
      case ArkeAuth.Guardian.get_member(conn) do
        %{arke_id: :super_admin} ->
          conn

        _ ->
          {:error, msg} = Error.create(:auth, "forbidden")

          conn
          |> ArkeServer.ResponseManager.send_resp(403, nil, msg)
          |> Plug.Conn.halt()
      end
    end
  end
end
