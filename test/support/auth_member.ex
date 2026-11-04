defmodule ArkeServer.Support.AuthMember do
  @moduledoc """
  A member arke in `test_schema` that is not `super_admin`, with an `email`,
  for the auth flows that look members up by email or treat admins apart.

  Arke managers live in memory across the SQL sandbox, so the arke is created
  once per test run and reused.
  """
  alias Arke.Boundary.ArkeManager
  alias Arke.{LinkManager, QueryManager}

  @project :test_schema
  @arke_id :test_auth_member

  def arke_id, do: @arke_id

  def ensure_arke(groups \\ ["arke_auth_member"]) do
    if is_nil(ArkeManager.get(@arke_id, @project)) do
      QueryManager.create(@project, ArkeManager.get(:arke, :arke_system), %{
        id: to_string(@arke_id),
        label: "Test auth member"
      })

      for parameter <- ["arke_system_user", "email"],
          do: LinkManager.add_node(@project, to_string(@arke_id), parameter, "parameter")
    end

    for group <- groups, do: add_to_group(group)

    ArkeManager.get(@arke_id, @project)
  end

  def add_to_group(group) do
    case Arke.Boundary.GroupManager.get(String.to_existing_atom(group), @project) do
      nil ->
        :ok

      group_unit ->
        ids = Arke.Boundary.GroupManager.get_arke_list(group_unit) |> Enum.map(& &1.id)

        unless @arke_id in ids,
          do: LinkManager.add_node(@project, group, to_string(@arke_id), "group")

        :ok
    end
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
      QueryManager.create(@project, ensure_arke(), %{
        arke_system_user: to_string(user.id),
        email: user.data.email
      })

    member
  end
end
