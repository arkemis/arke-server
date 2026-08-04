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

defmodule ArkeServer.Utils.OneSignal do
  def create_user(%{metadata: %{project: _project}} = member) do
    app_id = System.get_env("ONESIGNAL_APP_ID")

    data = %{
      properties: %{
        tags: %{
          first_name: member.data.first_name,
          last_name: member.data.last_name,
          email: member.data.email
        }
      },
      identity: %{
        id: member.id,
        external_id: member.id
      }
    }

    call_api(:post, "/apps/#{app_id}/users", data)
  end

  @doc """
  Creates a OneSignal push notification

  ## Parameter
    - member => single member or list of members
    - contents => %{key: value} => see OneSignal api docs for `contents` push notification map key.
    This has been kept for retrocompatibility, passing `contents` as a `custom_data` map key should now
    be preferred
    - custom_data => %{key: value} => see OneSignal api docs for push notifications. These are options for
    the soon-to-be-created notification
  """
  def create_notification(member, contents, custom_data \\ %{})

  def create_notification(member, contents, custom_data) when is_map(member),
    do: create_notification([member], contents, custom_data)

  def create_notification(members, contents, custom_data) when is_list(members) do
    external_id = Enum.map(members, fn m -> to_string(m.id) end)
    app_id = System.get_env("ONESIGNAL_APP_ID")

    data = %{
      app_id: app_id,
      target_channel: "push",
      include_aliases: %{external_id: external_id},
      contents: contents
    }

    call_api(:post, "/notifications", Map.merge(data, custom_data))
  end

  defp call_api(method, path, body, _opts \\ []) do
    api_token = System.get_env("ONESIGNAL_API_KEY")

    case Req.request(
           method: method,
           url: "https://onesignal.com/api/v1#{path}",
           json: body,
           headers: [{"authorization", "Basic #{api_token}"}],
           retry: false
         ) do
      {:ok, response} -> response.body
      {:error, error} -> {:error, error}
    end
  end
end
