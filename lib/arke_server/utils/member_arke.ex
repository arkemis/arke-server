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

defmodule ArkeServer.Utils.MemberArke do
  @moduledoc """
  Which member arkes a client may create a member of without an admin.

  A member arke is open to sign-up only if it is in the `self_signup` group,
  and to creation from an SSO login only if it is in `enable_sso`. It must
  also be an `arke_auth_member`. `super_admin` is always refused, so a project
  seeded before arke_auth emptied `enable_sso` stays safe.
  """
  alias Arke.Boundary.GroupManager

  @never [:super_admin]

  @doc "Whether anyone may sign up as a member of `arke_id` in `project`."
  @spec self_signup?(atom() | String.t() | nil, atom()) :: boolean()
  def self_signup?(arke_id, project), do: allowed?(arke_id, :self_signup, project)

  @doc "Whether an SSO login may create a member of `arke_id` in `project`."
  @spec sso_signup?(atom() | String.t() | nil, atom()) :: boolean()
  def sso_signup?(arke_id, project), do: allowed?(arke_id, :enable_sso, project)

  defp allowed?(arke_id, group, project) do
    case ArkeServer.Utils.ExistingAtom.get(arke_id) do
      nil ->
        false

      id when id in @never ->
        false

      id ->
        in_group?(id, group, project) and in_group?(id, :arke_auth_member, project)
    end
  end

  defp in_group?(arke_id, group_id, project) do
    case GroupManager.get(group_id, project) do
      nil -> false
      group -> Enum.any?(GroupManager.get_arke_list(group), &(&1.id == arke_id))
    end
  end
end
