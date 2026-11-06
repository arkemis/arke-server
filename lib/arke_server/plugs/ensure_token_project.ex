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

defmodule ArkeServer.Plugs.EnsureTokenProject do
  @moduledoc """
  Rejects a token issued for another project than the one the request
  targets (`conn.assigns[:arke_project]`).

  Member ids are only unique within a project and permissions are resolved
  in the requested project, so a token must not be replayed against another
  tenant. Run it inside a Guardian pipeline, after `Guardian.Plug.LoadResource`.

  ## Options
    * `:key` - the Guardian key of the token to check (default `:default`)
  """
  import Plug.Conn

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, opts) do
    key = Keyword.get(opts, :key, :default)
    project = conn.assigns[:arke_project] && to_string(conn.assigns[:arke_project])

    case Guardian.Plug.current_claims(conn, key: key) do
      %{"sub" => %{"project" => ^project}} when is_binary(project) ->
        conn

      _ ->
        handler = Guardian.Plug.Pipeline.fetch_error_handler!(conn, opts)

        conn
        |> handler.auth_error({:invalid_project, :token_project_mismatch}, opts)
        |> halt()
    end
  end
end
