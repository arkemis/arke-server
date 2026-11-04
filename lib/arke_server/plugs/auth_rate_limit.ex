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

defmodule ArkeServer.Plugs.AuthRateLimit do
  @moduledoc """
  Per-client rate limit on the `/lib/auth` endpoints (sign-in, sign-up, OTP,
  password recovery and reset, refresh, SSO). arke_auth locks an account
  after repeated failed passwords and burns an OTP after repeated wrong
  codes; this limit adds a cap per source address, across accounts.

  Over the limit the request is answered 429 with a `retry-after` header.

      config :arke_server, ArkeServer.Plugs.AuthRateLimit,
        enabled: true,          # default
        limit: 30,              # requests per client and window (default)
        window_ms: 60_000,      # default
        forwarded_header: nil   # e.g. "x-forwarded-for"

  Behind a reverse proxy every request comes from the proxy's address, so
  all clients would share one budget. Set `:forwarded_header` to the header
  your proxy writes: the last address in it, the one the proxy itself
  appended, is used. Only set it when a proxy you control always writes the
  header, since clients can send it too.
  """
  import Plug.Conn
  alias Arke.Utils.ErrorGenerator, as: Error

  @defaults [enabled: true, limit: 30, window_ms: 60_000, forwarded_header: nil]

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _opts) do
    config = config()

    if config[:enabled], do: limit(conn, config), else: conn
  end

  defp limit(conn, config) do
    key = "arke_auth:" <> client_ip(conn, config[:forwarded_header])

    case ArkeServer.RateLimit.hit(key, config[:window_ms], config[:limit]) do
      {:allow, _count} ->
        conn

      {:deny, retry_after_ms} ->
        {:error, msg} = Error.create(:auth, "too many requests")

        conn
        |> put_resp_header("retry-after", to_string(max(div(retry_after_ms, 1000), 1)))
        |> ArkeServer.ResponseManager.send_resp(429, nil, msg)
        |> halt()
    end
  end

  defp client_ip(conn, nil), do: format_ip(conn.remote_ip)

  defp client_ip(conn, header) do
    conn
    |> get_req_header(String.downcase(header))
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
    |> case do
      nil -> format_ip(conn.remote_ip)
      ip -> ip
    end
  end

  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp format_ip(ip), do: to_string(ip)

  defp config(),
    do: Keyword.merge(@defaults, Application.get_env(:arke_server, __MODULE__, []))
end
