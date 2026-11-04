defmodule ArkeServer.Support.AuthMember do
  @moduledoc """
  A member arke in `test_schema` that is not `super_admin`, with an `email`,
  for the auth flows that look members up by email or treat admins apart.
  It is in the `arke_auth_member` and `self_signup` groups.

  `setup!/0` runs once from test_helper.exs, outside the SQL sandbox: the
  arke managers keep units in memory across tests, so the rows they point at
  must not be rolled back.
  """
  alias Arke.Boundary.{ArkeManager, ParameterManager}
  alias Arke.{LinkManager, QueryManager}

  @project :test_schema
  @arke_id :test_auth_member

  def arke_id, do: @arke_id

  def setup!() do
    {:ok, _} =
      QueryManager.create(@project, ArkeManager.get(:arke, :arke_system), %{
        id: to_string(@arke_id),
        label: "Test auth member"
      })

    # arke_auth reads `inactive` but no registry defines it
    if is_nil(ParameterManager.get(:inactive, @project)) do
      {:ok, _} =
        QueryManager.create(@project, ArkeManager.get(:boolean, :arke_system), %{
          id: "inactive",
          label: "Inactive",
          default_boolean: false
        })
    end

    for parameter <- ["arke_system_user", "email", "inactive"],
        do: {:ok, _} = LinkManager.add_node(@project, to_string(@arke_id), parameter, "parameter")

    for group <- ["arke_auth_member", "self_signup"],
        do: {:ok, _} = LinkManager.add_node(@project, group, to_string(@arke_id), "group")

    :ok
  end

  @doc "Creates a user whose only member in `test_schema` is a #{@arke_id}."
  def create_user(username) do
    {:ok, user} =
      QueryManager.create(:arke_system, ArkeManager.get(:user, :arke_system), %{
        username: username,
        password: "password",
        email: "#{username}@arke.test"
      })

    {user, create(user)}
  end

  def create(user) do
    {:ok, member} =
      QueryManager.create(@project, ArkeManager.get(@arke_id, @project), %{
        arke_system_user: to_string(user.id),
        email: user.data.email
      })

    member
  end
end
