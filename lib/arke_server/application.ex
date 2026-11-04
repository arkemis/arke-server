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

defmodule ArkeServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    filter_sensitive_parameters()

    children = [
      # Start the Telemetry supervisor
      ArkeServer.Telemetry,
      # Start the Endpoint (http/https)
      ArkeServer.Endpoint
      # Start a worker by calling: ArkeServer.Worker.start_link(arg)
      # {ArkeServer.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArkeServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Request parameter names that must never reach the logs. Phoenix matches
  # them as substrings: "token" covers auth_token, refresh_token, id_token,
  # access_token and the reset password token; "password" covers new_password
  # and old_password.
  @sensitive_parameters ["password", "token", "otp", "secret"]

  # The auth endpoints receive credentials as parameters, so they are added to
  # the application's own :filter_parameters. A {:keep, list} allow-list is
  # left alone, since it already hides everything it does not name.
  defp filter_sensitive_parameters() do
    case Application.get_env(:phoenix, :filter_parameters, ["password"]) do
      params when is_list(params) ->
        Application.put_env(
          :phoenix,
          :filter_parameters,
          Enum.uniq(params ++ @sensitive_parameters)
        )

      _keep ->
        :ok
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ArkeServer.Endpoint.config_change(changed, removed)
    :ok
  end
end
