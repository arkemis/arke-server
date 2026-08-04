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

defmodule ArkeServer.Plugs.BuildFilters do
  import Plug.Conn
  alias ArkeServer.Utils.QueryFilters

  def init(default), do: default

  def call(%Plug.Conn{method: "GET", query_params: %{"filter" => condition}} = conn, _default) do
    case QueryFilters.get_from_string(conn, condition) do
      {:ok, data} -> assign(conn, :filter, data)
      {:error, msg} -> stop_conn(conn, msg)
    end
  end

  def call(conn, _opts), do: conn

  defp stop_conn(conn, errors) do
    ArkeServer.ResponseManager.send_resp(conn, 400, nil, errors)
    |> Plug.Conn.halt()
  end
end
